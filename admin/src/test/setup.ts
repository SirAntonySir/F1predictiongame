import '@testing-library/jest-dom/vitest'

// jsdom doesn't implement ResizeObserver, which Radix overlay components
// (AlertDialog/Dialog content use an internal ScrollArea) require at mount.
// Provide a no-op polyfill so those components render under test.
globalThis.ResizeObserver = class {
  observe() {}
  unobserve() {}
  disconnect() {}
} as unknown as typeof ResizeObserver

// Radix Select relies on Pointer Capture and scrollIntoView, neither of which
// jsdom implements. Stub them so the dropdown can open and items be clicked.
Element.prototype.hasPointerCapture = () => false
Element.prototype.setPointerCapture = () => {}
Element.prototype.releasePointerCapture = () => {}
Element.prototype.scrollIntoView = () => {}
