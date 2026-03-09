import {
  setPortalHoverColor,
  removeQueryParamsFromUrl,
  updateThemeInHeader,
  switchTheme,
  initializeThemeHandlers,
  initializeMediaQueryListener,
  initializeTheme,
} from '../portalThemeHelper.js';
import { adjustColorForContrast } from '../../shared/helpers/colorHelper.js';

describe('portalThemeHelper', () => {
  let themeToggleButton;
  let appearanceDropdown;
  let setPropertySpy;

  beforeEach(() => {
    localStorage.clear();

    themeToggleButton = document.createElement('div');
    themeToggleButton.id = 'toggle-appearance';
    document.body.appendChild(themeToggleButton);

    appearanceDropdown = document.createElement('div');
    appearanceDropdown.id = 'appearance-dropdown';
    appearanceDropdown.classList.add('appearance-menu');
    document.body.appendChild(appearanceDropdown);

    window.matchMedia = vi.fn().mockImplementation(query => ({
      matches: query === '(prefers-color-scheme: dark)',
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    }));

    window.portalConfig = { portalColor: '#ff5733' };
    setPropertySpy = vi.spyOn(document.documentElement.style, 'setProperty');
    document.documentElement.classList.remove('dark', 'light');
  });

  afterEach(() => {
    themeToggleButton.remove();
    appearanceDropdown.remove();
    delete window.portalConfig;
    setPropertySpy.mockRestore();
    document.documentElement.classList.remove('dark', 'light');
    localStorage.clear();
    vi.restoreAllMocks();
  });

  describe('#setPortalHoverColor', () => {
    it('should apply dark hover color in dark theme', () => {
      const hoverColor = adjustColorForContrast('#ff5733', '#151718');
      setPortalHoverColor('dark');
      expect(setPropertySpy).toHaveBeenCalledWith(
        '--dynamic-hover-color',
        hoverColor
      );
    });

    it('should apply light hover color in light theme', () => {
      const hoverColor = adjustColorForContrast('#ff5733', '#ffffff');
      setPortalHoverColor('light');
      expect(setPropertySpy).toHaveBeenCalledWith(
        '--dynamic-hover-color',
        hoverColor
      );
    });
  });

  describe('#removeQueryParamsFromUrl', () => {
    let replaceStateSpy;

    beforeEach(() => {
      replaceStateSpy = vi
        .spyOn(window.history, 'replaceState')
        .mockImplementation(() => {});
    });

    it('should not remove query params if theme is not in the URL', () => {
      removeQueryParamsFromUrl();
      expect(replaceStateSpy).not.toHaveBeenCalled();
    });

    it('should remove theme query param from the URL', () => {
      // Push a URL with query params so window.location.href reflects them
      window.history.pushState({}, '', '/?theme=light&show_plain_layout=true');
      removeQueryParamsFromUrl('theme');
      expect(replaceStateSpy).toHaveBeenCalledWith(
        {},
        '',
        expect.stringContaining('show_plain_layout=true')
      );
      expect(replaceStateSpy).toHaveBeenCalledWith(
        {},
        '',
        expect.not.stringContaining('theme=')
      );
      // Reset URL
      window.history.pushState({}, '', '/');
    });
  });

  describe('#updateThemeInHeader', () => {
    beforeEach(() => {
      themeToggleButton.innerHTML = `
        <div class="theme-button" data-theme="light"></div>
        <div class="theme-button" data-theme="dark"></div>
        <div class="theme-button" data-theme="system"></div>
      `;
    });

    it('should not update header if theme toggle button is not found', () => {
      themeToggleButton.remove();
      updateThemeInHeader('light');
      expect(document.querySelector('.theme-button')).toBeNull();
    });

    it('should show the theme button for the selected theme', () => {
      updateThemeInHeader('light');
      const lightButton = themeToggleButton.querySelector(
        '.theme-button[data-theme="light"]'
      );
      expect(lightButton.classList).toContain('flex');
    });
  });

  describe('#switchTheme', () => {
    it('should set theme to system theme and update classes', () => {
      window.matchMedia = vi.fn().mockReturnValue({ matches: true });
      switchTheme('system');
      expect(localStorage.getItem('theme')).toBeNull();
      expect(document.documentElement.classList).toContain('dark');
    });

    it('should set theme to light theme and update classes', () => {
      switchTheme('light');
      expect(localStorage.getItem('theme')).toBe('light');
      expect(document.documentElement.classList).toContain('light');
    });

    it('should set theme to dark theme and update classes', () => {
      switchTheme('dark');
      expect(localStorage.getItem('theme')).toBe('dark');
      expect(document.documentElement.classList).toContain('dark');
    });
  });

  describe('#initializeThemeHandlers', () => {
    beforeEach(() => {
      appearanceDropdown.innerHTML = `
        <button data-theme="light"><span class="check-mark-icon light-theme"></span></button>
        <button data-theme="dark"><span class="check-mark-icon dark-theme"></span></button>
        <button data-theme="system"><span class="check-mark-icon system-theme"></span></button>
      `;
    });

    it('does nothing if the appearance dropdown is not found', () => {
      appearanceDropdown.remove();
      expect(() => initializeThemeHandlers()).not.toThrow();
    });

    it('should handle theme button clicks', () => {
      initializeThemeHandlers();

      const lightButton = appearanceDropdown.querySelector(
        'button[data-theme="light"]'
      );
      lightButton.click();

      expect(localStorage.getItem('theme')).toBe('light');
      expect(appearanceDropdown.dataset.currentTheme).toBe('light');
    });

    it('should toggle dropdown visibility on toggle button click', () => {
      initializeThemeHandlers();

      expect(appearanceDropdown.dataset.dropdownOpen).toBeUndefined();

      themeToggleButton.click();
      expect(appearanceDropdown.dataset.dropdownOpen).toBe('true');

      themeToggleButton.click();
      expect(appearanceDropdown.dataset.dropdownOpen).toBe('false');
    });

    it('should close dropdown when clicking outside', () => {
      initializeThemeHandlers();

      appearanceDropdown.dataset.dropdownOpen = 'true';

      const outsideEl = document.createElement('div');
      document.body.appendChild(outsideEl);
      outsideEl.click();

      expect(appearanceDropdown.dataset.dropdownOpen).toBe('false');
      outsideEl.remove();
    });
  });

  describe('#initializeMediaQueryListener', () => {
    let mediaQuery;

    beforeEach(() => {
      mediaQuery = {
        addEventListener: vi.fn(),
        matches: false,
      };
      window.matchMedia = vi.fn().mockReturnValue(mediaQuery);
    });

    it('adds a listener to the media query', () => {
      initializeMediaQueryListener();
      expect(window.matchMedia).toHaveBeenCalledWith(
        '(prefers-color-scheme: dark)'
      );
      expect(mediaQuery.addEventListener).toHaveBeenCalledWith(
        'change',
        expect.any(Function)
      );
    });

    it('does not switch theme if local storage theme is light or dark', () => {
      localStorage.setItem('theme', 'light');
      initializeMediaQueryListener();
      mediaQuery.matches = true;
      mediaQuery.addEventListener.mock.calls[0][1]();
      expect(localStorage.getItem('theme')).toBe('light');
    });

    it('switches to dark theme if system preference changes to dark and no theme is set in local storage', () => {
      localStorage.removeItem('theme');
      initializeMediaQueryListener();
      mediaQuery.matches = true;
      mediaQuery.addEventListener.mock.calls[0][1]();
      expect(document.documentElement.classList).toContain('dark');
    });

    it('switches to light theme if system preference changes to light and no theme is set in local storage', () => {
      localStorage.removeItem('theme');
      initializeMediaQueryListener();
      mediaQuery.matches = false;
      mediaQuery.addEventListener.mock.calls[0][1]();
      expect(document.documentElement.classList).toContain('light');
    });
  });

  describe('#initializeTheme', () => {
    it('should not initialize theme if plain layout is enabled', () => {
      window.portalConfig.isPlainLayoutEnabled = 'true';
      initializeTheme();
      expect(localStorage.getItem('theme')).toBeNull();
      expect(document.documentElement.classList).not.toContain('light');
      expect(document.documentElement.classList).not.toContain('dark');
    });

    it('sets the theme to the system theme', () => {
      initializeTheme();
      expect(localStorage.getItem('theme')).toBeNull();
      const prefersDarkMode = window.matchMedia(
        '(prefers-color-scheme: dark)'
      ).matches;
      expect(document.documentElement.classList.contains('light')).toBe(
        !prefersDarkMode
      );
    });

    it('sets the theme to the light theme', () => {
      localStorage.setItem('theme', 'light');
      document.documentElement.classList.add('light');
      initializeTheme();
      expect(localStorage.getItem('theme')).toBe('light');
      expect(document.documentElement.classList.contains('light')).toBe(true);
    });

    it('sets the theme to the dark theme', () => {
      localStorage.setItem('theme', 'dark');
      document.documentElement.classList.add('dark');
      initializeTheme();
      expect(localStorage.getItem('theme')).toBe('dark');
      expect(document.documentElement.classList.contains('dark')).toBe(true);
    });
  });
});
