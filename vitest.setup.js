import { config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import i18nMessages from 'dashboard/i18n';
import FloatingVue from 'floating-vue';

// jsdom's localStorage may be broken when --localstorage-file is misconfigured.
// Provide a reliable global mock that supports both the Storage API and direct
// property access (e.g. localStorage.theme = 'dark').
if (typeof window.localStorage?.setItem !== 'function') {
  const store = {};
  const storageMock = {
    getItem: key => (key in store ? store[key] : null),
    setItem: (key, value) => {
      store[key] = String(value);
    },
    removeItem: key => delete store[key],
    clear: () => Object.keys(store).forEach(k => delete store[k]),
    get length() {
      return Object.keys(store).length;
    },
    key: index => Object.keys(store)[index] ?? null,
  };
  const proxy = new Proxy(storageMock, {
    get: (target, prop) => (prop in target ? target[prop] : target.getItem(prop)),
    set: (target, prop, value) => { target.setItem(prop, value); return true; },
    deleteProperty: (target, prop) => { target.removeItem(prop); return true; },
  });
  Object.defineProperty(window, 'localStorage', {
    value: proxy,
    writable: true,
    configurable: true,
  });
}

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: i18nMessages,
});

config.global.plugins = [i18n, FloatingVue];
config.global.stubs = {
  WootModal: { template: '<div><slot/></div>' },
  WootModalHeader: { template: '<div><slot/></div>' },
  NextButton: { template: '<button><slot/></button>' },
};
