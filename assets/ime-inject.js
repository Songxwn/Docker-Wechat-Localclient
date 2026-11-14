// ==UserScript==
// @name         Selkies IME 无感粘贴（公开版）
// @namespace    local.selkies.ime
// @version      0.3.4
// @description  无感截获输入法提交，通过远端剪贴板整体粘贴，避免临时内容回写本机剪贴板。
// @author       local
// @include      /^https?:\/\/[^/]+:(?:13000|13001)\/.*$/
// @run-at       document-start
// @grant        unsafeWindow
// ==/UserScript==

/*
 * 公开版安装说明：
 * 1. 默认匹配任意主机上使用 HTTP/HTTPS 的 3000 或 3001 端口。
 * 2. 如果通过反向代理使用其他端口，请按实际地址修改上方 @include。
 * 3. 脚本仅在事件目标为 Selkies 的 #overlayInput 时处理输入，不会上传文字。
 */

(function () {
    'use strict';

    const pageWindow = typeof unsafeWindow === 'undefined' ? window : unsafeWindow;
    const CONFIG = Object.freeze({
        nativeTextWaitMs: 280,
        nativeTextReleaseGraceMs: 40,
        nativePasteEchoMs: 250,
        compositionIdleTimeoutMs: 8000,
        messageGapMs: 120,
        transportRetryMs: 500,
        modifierPollMs: 8,
        modifierStaleMs: 5000,
        postCommitSuppressionMs: 400,
        clipboardEchoGuardMs: 1500,
    });
    const X11_KEYSYM = Object.freeze({
        CONTROL_LEFT: 0xffe3,
        V: 0x76,
    });
    const TEXT_PHYSICAL_CODES = new Set([
        'Backquote', 'Minus', 'Equal', 'BracketLeft', 'BracketRight',
        'Backslash', 'Semicolon', 'Quote', 'Comma', 'Period', 'Slash',
        'IntlBackslash', 'IntlRo', 'IntlYen', 'Space',
        'Numpad0', 'Numpad1', 'Numpad2', 'Numpad3', 'Numpad4',
        'Numpad5', 'Numpad6', 'Numpad7', 'Numpad8', 'Numpad9',
        'NumpadDecimal', 'NumpadAdd', 'NumpadSubtract',
        'NumpadMultiply', 'NumpadDivide',
    ]);

    const state = {
        mode: 'idle',
        compositionTarget: null,
        textInputCommit: '',
        compositionWatchdog: null,
        pendingNativeText: null,
        nativePasteEcho: null,
        suppressTextEventsUntil: 0,
        blockedKeyCodes: new Set(),
        heldModifiers: new Set(),
        lastModifierReleaseAt: -Infinity,
        pageActive: true,
        queue: [],
        flushing: false,
        clipboardEchoGuards: [],
        clipboardPatchedMethods: new Set(),
        clipboardPatchWarningShown: false,
    };

    const delay = (milliseconds) => new Promise((resolve) => {
        window.setTimeout(resolve, milliseconds);
    });

    function isSelkiesInputTarget(target) {
        return Boolean(target && target.id === 'overlayInput');
    }

    function stopSelkiesHandling(event) {
        // 不调用 preventDefault：浏览器仍需执行本机 IME 和透明输入框的默认行为。
        event.stopImmediatePropagation();
    }

    function getSelkiesInput() {
        const input = pageWindow.webrtcInput;
        return input && typeof input.send === 'function' ? input : null;
    }

    function encodeUtf8Base64(text) {
        const bytes = new TextEncoder().encode(text);
        const chunks = [];
        const chunkSize = 0x8000;

        for (let offset = 0; offset < bytes.length; offset += chunkSize) {
            chunks.push(String.fromCharCode(...bytes.subarray(offset, offset + chunkSize)));
        }

        return btoa(chunks.join(''));
    }

    function pruneClipboardEchoGuards() {
        const now = performance.now();
        state.clipboardEchoGuards = state.clipboardEchoGuards.filter((guard) => guard.expiresAt > now);
    }

    function removeClipboardEchoGuard(guard) {
        if (!guard) return;
        const index = state.clipboardEchoGuards.indexOf(guard);
        if (index >= 0) state.clipboardEchoGuards.splice(index, 1);
    }

    function consumeClipboardEchoByText(text) {
        pruneClipboardEchoGuards();
        const index = state.clipboardEchoGuards.findIndex((guard) => guard.text === String(text));
        if (index < 0) return false;
        state.clipboardEchoGuards.splice(index, 1);
        return true;
    }

    function consumeNextClipboardTextEcho(items) {
        pruneClipboardEchoGuards();
        if (state.clipboardEchoGuards.length === 0) return false;

        const carriesPlainText = Array.from(items || []).some((item) =>
            item && Array.from(item.types || []).includes('text/plain'));
        if (!carriesPlainText) return false;

        // ClipboardItem 的正文只能异步读取。这里利用 cw 后紧接着产生回流的顺序，
        // 只吞掉短时间窗内第一笔纯文本 write，不延迟其它正常剪贴板写入。
        state.clipboardEchoGuards.shift();
        return true;
    }

    function replaceClipboardMethod(clipboard, methodName, replacement) {
        const original = clipboard && clipboard[methodName];
        if (typeof original !== 'function') return false;

        const descriptor = {
            configurable: true,
            enumerable: false,
            writable: true,
            value: replacement(original),
        };

        try {
            Object.defineProperty(clipboard, methodName, descriptor);
            return true;
        } catch (_) {
            const prototype = Object.getPrototypeOf(clipboard);
            if (!prototype) return false;
            try {
                Object.defineProperty(prototype, methodName, descriptor);
                return true;
            } catch (error) {
                console.warn(`[Selkies IME] 无法拦截 clipboard.${methodName}。`, error);
                return false;
            }
        }
    }

    function installClipboardEchoGuard() {
        const clipboard = pageWindow.navigator && pageWindow.navigator.clipboard;
        if (!clipboard) return false;

        if (!state.clipboardPatchedMethods.has('writeText') && typeof clipboard.writeText === 'function') {
            const patched = replaceClipboardMethod(clipboard, 'writeText', (original) => function (text) {
                if (consumeClipboardEchoByText(text)) {
                    console.debug('[Selkies IME] 已阻止临时输入回写本机剪贴板。');
                    return pageWindow.Promise.resolve();
                }
                return original.call(this, text);
            });
            if (patched) state.clipboardPatchedMethods.add('writeText');
        }

        if (!state.clipboardPatchedMethods.has('write') && typeof clipboard.write === 'function') {
            const patched = replaceClipboardMethod(clipboard, 'write', (original) => function (items) {
                if (consumeNextClipboardTextEcho(items)) {
                    console.debug('[Selkies IME] 已阻止临时输入回写本机剪贴板。');
                    return pageWindow.Promise.resolve();
                }
                return original.call(this, items);
            });
            if (patched) state.clipboardPatchedMethods.add('write');
        }

        // Chromium/Selkies 优先使用 write(ClipboardItem)，只有该接口不存在时才退回 writeText。
        // 不能把仅成功拦截备用接口误判为保护已经生效。
        return typeof clipboard.write === 'function'
            ? state.clipboardPatchedMethods.has('write')
            : state.clipboardPatchedMethods.has('writeText');
    }

    function armClipboardEchoGuard(text) {
        if (!installClipboardEchoGuard()) {
            if (!state.clipboardPatchWarningShown) {
                state.clipboardPatchWarningShown = true;
                console.warn('[Selkies IME] 浏览器剪贴板接口不可拦截，临时输入可能同步到本机剪贴板。');
            }
            return null;
        }

        pruneClipboardEchoGuards();
        const guard = {
            text,
            expiresAt: performance.now() + CONFIG.clipboardEchoGuardMs,
        };
        state.clipboardEchoGuards.push(guard);
        return guard;
    }

    function sendRemoteKey(selkiesInput, keysym, down) {
        selkiesInput.send(`${down ? 'kd' : 'ku'},${keysym}`);
    }

    function sendClipboardPaste(selkiesInput, text) {
        // 服务端按连接顺序同步处理 cw，紧随其后的 Ctrl+V 会读取刚写入的内容。
        const clipboardEchoGuard = armClipboardEchoGuard(text);
        try {
            selkiesInput.send(`cw,${encodeUtf8Base64(text)}`);
            sendRemoteKey(selkiesInput, X11_KEYSYM.CONTROL_LEFT, true);
            sendRemoteKey(selkiesInput, X11_KEYSYM.V, true);
            sendRemoteKey(selkiesInput, X11_KEYSYM.V, false);
            sendRemoteKey(selkiesInput, X11_KEYSYM.CONTROL_LEFT, false);
        } catch (error) {
            removeClipboardEchoGuard(clipboardEchoGuard);
            throw error;
        }
    }

    function syncHeldModifiers(event) {
        const previouslyHeld = state.heldModifiers.size > 0;
        state.heldModifiers.clear();
        if (event.shiftKey) state.heldModifiers.add('Shift');
        if (event.ctrlKey) state.heldModifiers.add('Control');
        if (event.altKey) state.heldModifiers.add('Alt');
        if (event.metaKey) state.heldModifiers.add('Meta');

        if (previouslyHeld && state.heldModifiers.size === 0) {
            state.lastModifierReleaseAt = performance.now();
            window.setTimeout(() => void flushQueue(), 0);
        }
    }

    function clearStaleModifiers() {
        const selkiesInput = getSelkiesInput();
        if (selkiesInput && typeof selkiesInput.resetKeyboard === 'function') {
            selkiesInput.resetKeyboard();
        }
        state.heldModifiers.clear();
        state.lastModifierReleaseAt = performance.now();
    }

    async function waitUntilPasteIsSafe(item) {
        while (!state.pageActive) await delay(CONFIG.transportRetryMs);

        while (state.heldModifiers.size > 0) {
            if (performance.now() - item.queuedAt >= CONFIG.modifierStaleMs) {
                clearStaleModifiers();
                break;
            }
            await delay(CONFIG.modifierPollMs);
        }

        // 让当前 keyup 先到达 Selkies，再在下一个任务中发送 Ctrl+V。
        if (Number.isFinite(state.lastModifierReleaseAt)) await delay(0);
    }

    async function flushQueue() {
        if (state.flushing) return;
        state.flushing = true;

        try {
            while (state.queue.length > 0) {
                const item = state.queue[0];
                await waitUntilPasteIsSafe(item);

                const selkiesInput = getSelkiesInput();
                if (!selkiesInput) {
                    await delay(CONFIG.transportRetryMs);
                    continue;
                }

                try {
                    sendClipboardPaste(selkiesInput, item.text);
                    state.queue.shift();
                    console.debug('[Selkies IME] 已通过远端剪贴板粘贴：', item.text);
                    // 给远端应用读取本次 X11 剪贴板的时间，再覆盖成下一段。
                    await delay(CONFIG.messageGapMs);
                } catch (error) {
                    console.warn('[Selkies IME] 粘贴失败，稍后重试。', error);
                    await delay(CONFIG.transportRetryMs);
                }
            }
        } finally {
            state.flushing = false;
        }
    }

    function normalizeText(text) {
        return String(text || '').replace(/[\r\n]+/g, '');
    }

    function isPasteLikeInputType(inputType) {
        return /(?:paste|drop|yank)/i.test(String(inputType || ''));
    }

    function readTransferText(transfer) {
        if (!transfer || typeof transfer.getData !== 'function') return '';
        try {
            return normalizeText(transfer.getData('text/plain'));
        } catch (error) {
            console.debug('[Selkies IME] 无法读取本机粘贴文本，仅按事件类型过滤。', error);
            return '';
        }
    }

    function rememberNativePasteEcho(target, text) {
        clearPendingNativeText();
        if (state.mode === 'waiting-native-text') state.mode = 'idle';
        state.nativePasteEcho = {
            target,
            text: normalizeText(text),
            expiresAt: performance.now() + CONFIG.nativePasteEchoMs,
        };
    }

    function shouldIgnoreNativePasteEcho(event) {
        if (isPasteLikeInputType(event.inputType)) {
            rememberNativePasteEcho(event.target, event.data);
            return true;
        }

        const echo = state.nativePasteEcho;
        if (!echo) return false;
        if (performance.now() > echo.expiresAt || event.target !== echo.target) {
            state.nativePasteEcho = null;
            return false;
        }

        const eventText = normalizeText(event.data);
        // textInput 通常没有 inputType；仅忽略同一目标、同一内容的紧随回声。
        return Boolean(eventText && (!echo.text || eventText === echo.text));
    }

    function enqueueText(text) {
        const normalized = normalizeText(text);
        if (!normalized) return;

        state.queue.push({ text: normalized, queuedAt: performance.now() });
        void flushQueue();
    }

    function clearCompositionHostSoon(target) {
        window.setTimeout(() => {
            if (state.mode !== 'composing' && target && typeof target.value === 'string') {
                target.value = '';
            }
        }, 0);
    }

    function clearPendingNativeText() {
        const pending = state.pendingNativeText;
        if (pending && pending.timer !== null) window.clearTimeout(pending.timer);
        state.pendingNativeText = null;
    }

    function clearCompositionWatchdog() {
        if (state.compositionWatchdog === null) return;
        window.clearTimeout(state.compositionWatchdog);
        state.compositionWatchdog = null;
    }

    function armCompositionWatchdog(target) {
        clearCompositionWatchdog();
        state.compositionWatchdog = window.setTimeout(() => {
            state.compositionWatchdog = null;
            if (state.mode !== 'composing' || state.compositionTarget !== target) return;

            state.mode = 'idle';
            state.compositionTarget = null;
            state.textInputCommit = '';
            state.suppressTextEventsUntil = performance.now() + CONFIG.postCommitSuppressionMs;
            state.blockedKeyCodes.clear();
            state.heldModifiers.clear();
            state.lastModifierReleaseAt = performance.now();
            clearCompositionHostSoon(target);

            const selkiesInput = getSelkiesInput();
            if (selkiesInput && typeof selkiesInput.resetKeyboard === 'function') {
                selkiesInput.resetKeyboard();
            }
            console.warn('[Selkies IME] 组词事件超时，已自动恢复输入状态。');
        }, CONFIG.compositionIdleTimeoutMs);
    }

    function fallbackShiftCharacter(event) {
        if (event.shiftKey && /^Key[A-Z]$/.test(event.code)) {
            return event.code.slice(3).toUpperCase();
        }
        if (typeof event.getModifierState === 'function' && event.getModifierState('CapsLock') &&
            /^Key[A-Z]$/.test(event.code)) {
            return event.code.slice(3).toUpperCase();
        }
        return '';
    }

    function beginNativeTextWait(event, appendShiftFallback = false) {
        const fallbackText = fallbackShiftCharacter(event);
        const current = state.pendingNativeText;
        if (appendShiftFallback && fallbackText && current &&
            current.target === event.target && current.waitForModifierRelease) {
            current.fallbackText += fallbackText;
            return;
        }

        clearPendingNativeText();
        const pending = {
            target: event.target,
            code: event.code,
            fallbackText,
            waitForModifierRelease: appendShiftFallback && event.shiftKey,
            waitedForModifierRelease: false,
            releaseGraceApplied: false,
            timer: null,
        };

        state.mode = 'waiting-native-text';
        state.pendingNativeText = pending;
        const finishFallback = () => {
            if (state.pendingNativeText !== pending) return;

            if (pending.waitForModifierRelease && state.heldModifiers.size > 0) {
                pending.waitedForModifierRelease = true;
                pending.timer = window.setTimeout(finishFallback, CONFIG.modifierPollMs);
                return;
            }

            if (pending.waitedForModifierRelease && !pending.releaseGraceApplied) {
                pending.releaseGraceApplied = true;
                pending.timer = window.setTimeout(finishFallback, CONFIG.nativeTextReleaseGraceMs);
                return;
            }

            state.pendingNativeText = null;
            state.mode = 'idle';
            if (pending.fallbackText) enqueueText(pending.fallbackText);
            clearCompositionHostSoon(pending.target);
        };
        pending.timer = window.setTimeout(finishFallback, CONFIG.nativeTextWaitMs);
    }

    function captureNativeText(text, target) {
        const normalized = normalizeText(text);
        if (!normalized) return false;

        clearPendingNativeText();
        state.mode = 'idle';
        state.suppressTextEventsUntil = performance.now() + CONFIG.postCommitSuppressionMs;
        enqueueText(normalized);
        clearCompositionHostSoon(target);
        return true;
    }

    function isProcessLike(event) {
        return event.isComposing || event.keyCode === 229 ||
            event.key === 'Process' || event.key === 'Unidentified';
    }

    function isTextPhysicalCode(code) {
        return /^Key[A-Z]$/.test(code) || /^Digit[0-9]$/.test(code) ||
            TEXT_PHYSICAL_CODES.has(code);
    }

    function hasChordModifier(event) {
        return event.ctrlKey || event.altKey || event.metaKey;
    }

    function shouldHandleAsAtomicText(text) {
        if (!text) return false;
        const characters = Array.from(text);
        return characters.length > 1 || characters.some((character) => character.codePointAt(0) > 0x7f);
    }

    function handleCompositionStart(event) {
        if (!isSelkiesInputTarget(event.target)) return;

        clearPendingNativeText();
        state.mode = 'composing';
        state.compositionTarget = event.target;
        state.textInputCommit = '';
        armCompositionWatchdog(event.target);
        stopSelkiesHandling(event);
    }

    function handleCompositionUpdate(event) {
        if (state.mode !== 'composing' || event.target !== state.compositionTarget) return;
        armCompositionWatchdog(event.target);
        stopSelkiesHandling(event);
    }

    function handleCompositionEnd(event) {
        if (state.mode !== 'composing' || event.target !== state.compositionTarget) return;

        stopSelkiesHandling(event);
        clearCompositionWatchdog();
        const committedText = event.data || state.textInputCommit;
        const target = state.compositionTarget;

        state.mode = 'idle';
        state.compositionTarget = null;
        state.textInputCommit = '';
        state.suppressTextEventsUntil = performance.now() + CONFIG.postCommitSuppressionMs;

        enqueueText(committedText);
        clearCompositionHostSoon(target);
    }

    function handleTextInput(event) {
        if (!isSelkiesInputTarget(event.target)) return;

        // 本机粘贴由 Selkies 自己同步；这里仅放行，不能再次加入脚本队列。
        if (shouldIgnoreNativePasteEcho(event)) return;

        if (state.mode === 'composing') {
            if (event.data) state.textInputCommit = event.data;
            armCompositionWatchdog(event.target);
            stopSelkiesHandling(event);
            return;
        }

        if (state.mode === 'waiting-native-text') {
            captureNativeText(event.data || event.target.value, event.target);
            stopSelkiesHandling(event);
            return;
        }

        if (performance.now() < state.suppressTextEventsUntil) {
            stopSelkiesHandling(event);
            return;
        }

        if (shouldHandleAsAtomicText(event.data)) {
            captureNativeText(event.data, event.target);
            stopSelkiesHandling(event);
        }
    }

    function handleBeforeInput(event) {
        if (!isSelkiesInputTarget(event.target)) return;

        if (shouldIgnoreNativePasteEcho(event)) return;

        if (state.mode === 'composing') {
            armCompositionWatchdog(event.target);
            stopSelkiesHandling(event);
            return;
        }

        if (state.mode === 'waiting-native-text') {
            if (!String(event.inputType || '').includes('Composition')) {
                captureNativeText(event.data, event.target);
            }
            stopSelkiesHandling(event);
            return;
        }

        if (performance.now() < state.suppressTextEventsUntil) {
            stopSelkiesHandling(event);
            return;
        }

        if (shouldHandleAsAtomicText(event.data)) {
            captureNativeText(event.data, event.target);
            stopSelkiesHandling(event);
        }
    }

    function handleInput(event) {
        if (!isSelkiesInputTarget(event.target)) return;

        if (shouldIgnoreNativePasteEcho(event)) return;

        if (state.mode === 'composing') {
            armCompositionWatchdog(event.target);
            stopSelkiesHandling(event);
            return;
        }

        if (state.mode === 'waiting-native-text') {
            captureNativeText(event.data || event.target.value, event.target);
            stopSelkiesHandling(event);
            return;
        }

        if (performance.now() < state.suppressTextEventsUntil) {
            stopSelkiesHandling(event);
            return;
        }

        if (shouldHandleAsAtomicText(event.data)) {
            captureNativeText(event.data, event.target);
            stopSelkiesHandling(event);
        }
    }

    function handleKeyDown(event) {
        if (!isSelkiesInputTarget(event.target)) return;
        syncHeldModifiers(event);

        if (state.mode === 'composing') {
            if (event.code) state.blockedKeyCodes.add(event.code);
            stopSelkiesHandling(event);
            return;
        }

        // Ctrl/Alt/Meta 组合键交回 Selkies；其内部负责 AltGr、macOS Command 映射和快捷键。
        if (hasChordModifier(event)) return;

        // 微软输入法有时把 Shift+字母报告成 Process/229。先阻止异常预编辑，
        // 再等待浏览器的实际文字事件；没有事件时才用大写字符兜底，避免重复提交。
        if (event.shiftKey && /^Key[A-Z]$/.test(event.code) && isProcessLike(event)) {
            if (event.code) state.blockedKeyCodes.add(event.code);
            event.preventDefault();
            beginNativeTextWait(event, true);
            stopSelkiesHandling(event);
            return;
        }

        if (isProcessLike(event) && isTextPhysicalCode(event.code)) {
            if (event.code) state.blockedKeyCodes.add(event.code);
            beginNativeTextWait(event);
            stopSelkiesHandling(event);
        }
    }

    function handlePaste(event) {
        if (!isSelkiesInputTarget(event.target)) return;
        rememberNativePasteEcho(event.target, readTransferText(event.clipboardData));
        // 不阻止默认行为、不停止传播：Selkies 仍需正常处理这次粘贴。
    }

    function handleDrop(event) {
        if (!isSelkiesInputTarget(event.target)) return;
        rememberNativePasteEcho(event.target, readTransferText(event.dataTransfer));
    }

    function handleKeyPress(event) {
        if (!isSelkiesInputTarget(event.target)) return;
        if (state.mode !== 'composing' && state.mode !== 'waiting-native-text') return;

        if (event.code) state.blockedKeyCodes.add(event.code);
        stopSelkiesHandling(event);
    }

    function handleKeyUp(event) {
        if (!isSelkiesInputTarget(event.target)) return;
        syncHeldModifiers(event);

        const blocked = event.code && state.blockedKeyCodes.has(event.code);
        if (blocked) state.blockedKeyCodes.delete(event.code);
        // 只吞掉与已拦截 keydown 成对的 keyup；已转发的 Shift 等修饰键必须正常释放。
        if (!blocked) return;
        stopSelkiesHandling(event);
    }

    function resetCaptureState(reason) {
        clearPendingNativeText();
        clearCompositionWatchdog();
        state.mode = 'idle';
        state.compositionTarget = null;
        state.textInputCommit = '';
        state.nativePasteEcho = null;
        state.suppressTextEventsUntil = 0;
        state.blockedKeyCodes.clear();
        state.heldModifiers.clear();
        state.lastModifierReleaseAt = performance.now();
        console.debug(`[Selkies IME] 输入状态已重置：${reason}`);
    }

    function handleWindowBlur() {
        state.pageActive = false;
        resetCaptureState('窗口失焦');
    }

    function handleWindowFocus() {
        state.pageActive = true;
        void flushQueue();
    }

    function handleVisibilityChange() {
        state.pageActive = document.visibilityState !== 'hidden';
        if (!state.pageActive) resetCaptureState('页面隐藏');
        else void flushQueue();
    }

    // capture=true 且 document-start 注册，先于 Selkies 的监听器处理输入事件。
    window.addEventListener('keydown', handleKeyDown, true);
    window.addEventListener('keyup', handleKeyUp, true);
    window.addEventListener('keypress', handleKeyPress, true);
    window.addEventListener('compositionstart', handleCompositionStart, true);
    window.addEventListener('compositionupdate', handleCompositionUpdate, true);
    window.addEventListener('compositionend', handleCompositionEnd, true);
    window.addEventListener('textInput', handleTextInput, true);
    window.addEventListener('beforeinput', handleBeforeInput, true);
    window.addEventListener('input', handleInput, true);
    window.addEventListener('paste', handlePaste, true);
    window.addEventListener('drop', handleDrop, true);
    window.addEventListener('blur', handleWindowBlur, true);
    window.addEventListener('focus', handleWindowFocus, true);
    window.addEventListener('pagehide', () => resetCaptureState('页面卸载'), true);
    document.addEventListener('visibilitychange', handleVisibilityChange, true);

    installClipboardEchoGuard();
    console.info('[Selkies IME] 无感剪贴板模式 0.3.4 已启用。');
})();
