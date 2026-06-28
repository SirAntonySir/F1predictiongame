import '@testing-library/jest-dom/vitest'

// jsdom doesn't implement ResizeObserver, which Radix overlay components
// (AlertDialog/Dialog content use an internal ScrollArea) require at mount.
// Provide a no-op polyfill so those components render under test.
globalThis.ResizeObserver = class {
  observe() {}
  unobserve() {}
  disconnect() {}
} as unknown as typeof ResizeObserver
