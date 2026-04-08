/**
 * Below are the colors that are used in the app. The colors are defined in the light and dark mode.
 * There are many other ways to style your app. For example, [Nativewind](https://www.nativewind.dev/), [Tamagui](https://tamagui.dev/), [unistyles](https://reactnativeunistyles.vercel.app), etc.
 */

import { Platform } from 'react-native';

const tintColorLight = '#0a7ea4';
const tintColorDark = '#fff';

export const Colors = {
  light: {
    // ── existing (nav/tab) ──
    text: '#11181C',
    background: '#fff',
    tint: tintColorLight,
    icon: '#687076',
    tabIconDefault: '#687076',
    tabIconSelected: tintColorLight,
    // ── design system ──
    textPrimary: '#000000',
    textSecondary: '#8F8F8F',
    border: '#EEEEEE',
    surface: '#EEEEEE',
  },
  dark: {
    // ── existing (nav/tab) ──
    text: '#ECEDEE',
    background: '#151718',
    tint: tintColorDark,
    icon: '#9BA1A6',
    tabIconDefault: '#9BA1A6',
    tabIconSelected: tintColorDark,
    // ── design system (estimated dark equivalents) ──
    textPrimary: '#FFFFFF',
    textSecondary: '#8F8F8F',
    border: '#2C2C2E',
    surface: '#2C2C2E',
  },
};

export const Fonts = Platform.select({
  ios: {
    /** iOS `UIFontDescriptorSystemDesignDefault` */
    sans: 'system-ui',
    /** iOS `UIFontDescriptorSystemDesignSerif` */
    serif: 'ui-serif',
    /** iOS `UIFontDescriptorSystemDesignRounded` */
    rounded: 'ui-rounded',
    /** iOS `UIFontDescriptorSystemDesignMonospaced` */
    mono: 'ui-monospace',
  },
  default: {
    sans: 'normal',
    serif: 'serif',
    rounded: 'normal',
    mono: 'monospace',
  },
  web: {
    sans: "system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif",
    serif: "Georgia, 'Times New Roman', serif",
    rounded: "'SF Pro Rounded', 'Hiragino Maru Gothic ProN', Meiryo, 'MS PGothic', sans-serif",
    mono: "SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace",
  },
});

// Inter family names as loaded by @expo-google-fonts/inter in app/_layout.tsx
export const InterFonts = {
  light:   'Inter_300Light',
  regular: 'Inter_400Regular',
  medium:  'Inter_500Medium',
} as const;

// Matches Figma spacing variables (px)
export const Spacing = {
  none: 0,
  xxs:  2,   // e.g. AI button inner gap
  xs:   4,   // spacing-xs
  sm:   8,   // spacing-sm
  md:   16,  // spacing-lg (Figma naming)
  lg:   24,  // spacing-xl (Figma naming)
  xl:   40,  // spacing-xxxl (Figma naming)
} as const;

// Matches Figma radius variables (px)
export const Radius = {
  none:  0,
  md:    12,
  lg:    16,
  xl:    24,
  round: 999,
} as const;

// Text style objects — spread directly into StyleSheet styles.
// lineHeight values are absolute px (React Native requires this).
export const Typography = {
  displayLg: {
    fontFamily: InterFonts.regular,
    fontSize: 28,
    fontWeight: '400' as const,
    lineHeight: 31,        // 28 × 1.1
    letterSpacing: -0.84,  // -3% of 28px
  },
  bodyMd: {
    fontFamily: InterFonts.regular,
    fontSize: 16,
    fontWeight: '400' as const,
    lineHeight: 19,        // 16 × 1.2
    letterSpacing: -0.32,
  },
  bodySm: {
    fontFamily: InterFonts.regular,
    fontSize: 12,
    fontWeight: '400' as const,
    lineHeight: 12,
  },
  labelSm: {
    fontFamily: InterFonts.medium,
    fontSize: 12,
    fontWeight: '500' as const,
    lineHeight: 12,
  },
} as const;
