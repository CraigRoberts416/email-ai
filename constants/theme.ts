/**
 * Design system for Decision Inbox — dark-first, editorial-feed aesthetic.
 * Two-weight type, near-black ground, coral accent reserved for unread + one
 * primary action per screen. No card containers; separation is bg space.
 */

import { Platform } from 'react-native';

// ─── Colors ──────────────────────────────────────────────────────────────
// Dark commitment. Light palette kept as a mirror in case we port later,
// but every component reads from Colors.dark by default (see resolveTheme).

const dark = {
  bg:            '#0B0B0F',
  surface:       '#14141A',
  elevated:      '#1C1C24',
  textPrimary:   '#F2F2F5',
  textSecondary: '#9AA0A6',
  textTertiary:  '#5C616B',
  border:        '#22242C',
  accent:        '#FF6B4A',
  accentPressed: '#E85A3D',
  danger:        '#FF4E5B',
  success:       '#4ADE80',
  warning:       '#FFB74A',
  overlay:       'rgba(255,255,255,0.04)',
  scrim:         'rgba(0,0,0,0.55)',
} as const;

const light = {
  bg:            '#FBFBFC',
  surface:       '#F1F1F4',
  elevated:      '#FFFFFF',
  textPrimary:   '#0A0A0F',
  textSecondary: '#5C616B',
  textTertiary:  '#9AA0A6',
  border:        '#E4E5EA',
  accent:        '#E85A3D',
  accentPressed: '#C94526',
  danger:        '#DC2E39',
  success:       '#16A34A',
  warning:       '#D97706',
  overlay:       'rgba(0,0,0,0.04)',
  scrim:         'rgba(0,0,0,0.35)',
} as const;

// Back-compat with existing files that still read `Colors.light.textPrimary` etc.
// New code should import Palette + useTheme() (below) but this keeps the tree
// building while we migrate.
export const Colors = {
  light: {
    text:              light.textPrimary,
    background:        light.bg,
    tint:              light.accent,
    icon:              light.textSecondary,
    tabIconDefault:    light.textTertiary,
    tabIconSelected:   light.accent,
    textPrimary:       light.textPrimary,
    textSecondary:     light.textSecondary,
    border:            light.border,
    surface:           light.surface,
  },
  dark: {
    text:              dark.textPrimary,
    background:        dark.bg,
    tint:              dark.accent,
    icon:              dark.textSecondary,
    tabIconDefault:    dark.textTertiary,
    tabIconSelected:   dark.accent,
    textPrimary:       dark.textPrimary,
    textSecondary:     dark.textSecondary,
    border:            dark.border,
    surface:           dark.surface,
  },
};

export const Palette = { dark, light };

// The app defaults to dark. When we add a proper theme provider, swap here.
export const Theme = dark;

// ─── Spacing ─────────────────────────────────────────────────────────────
// 4pt scale, role-named. `xl` (24) is the separator BETWEEN cards; there is
// no border and no divider — cards float on bg.

export const Spacing = {
  none:  0,
  xxs:   2,
  xs:    4,
  sm:    8,
  md:    12,
  lg:    16,
  xl:    24,
  '2xl': 32,
  '3xl': 48,
  '4xl': 64,
} as const;

// ─── Radii ───────────────────────────────────────────────────────────────

export const Radius = {
  none:    0,
  chip:    4,
  control: 10,
  media:   12,
  sheet:   20,
  round:   999,
  // Back-compat with existing components
  md:      12,
  lg:      16,
  xl:      24,
} as const;

// ─── Type system ─────────────────────────────────────────────────────────
// Two weights only: 400 Regular + 700 Bold. Hierarchy carries on size, hue,
// and space. Anything you'd reach for Medium 500 stays Regular 400.
//
// Note: iOS uses SF Pro (`system-ui` resolves to it). Android/web fall back
// to the platform sans. Inter remains loaded in _layout.tsx for legacy code.

const systemSans = Platform.select({
  ios:     'System',            // SF Pro
  android: 'sans-serif',
  default: 'System',
});

const systemBold = Platform.select({
  ios:     'System',
  android: 'sans-serif',
  default: 'System',
});

// Legacy — some existing files still import InterFonts. Keep the shape
// stable so unmigrated components don't crash.
export const InterFonts = {
  light:   'Inter_300Light',
  regular: 'Inter_400Regular',
  medium:  'Inter_500Medium',
} as const;

export const Fonts = Platform.select({
  ios: {
    sans:    'System',
    serif:   'ui-serif',
    rounded: 'ui-rounded',
    mono:    'ui-monospace',
  },
  default: {
    sans:    'normal',
    serif:   'serif',
    rounded: 'normal',
    mono:    'monospace',
  },
  web: {
    sans:    "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', Roboto, sans-serif",
    serif:   "Georgia, serif",
    rounded: "'SF Pro Rounded', sans-serif",
    mono:    "SFMono-Regular, Menlo, monospace",
  },
});

// Text style objects — spread directly into StyleSheet styles.
export const Type = {
  display: {
    fontFamily:    systemBold,
    fontSize:      32,
    fontWeight:    '700' as const,
    lineHeight:    38,
    letterSpacing: -0.4,
  },
  headline: {
    fontFamily:    systemBold,
    fontSize:      22,
    fontWeight:    '700' as const,
    lineHeight:    28,
    letterSpacing: -0.3,
  },
  sender: {
    fontFamily:    systemBold,
    fontSize:      15,
    fontWeight:    '700' as const,
    lineHeight:    20,
    letterSpacing: -0.1,
  },
  senderRead: {
    fontFamily:    systemSans,
    fontSize:      15,
    fontWeight:    '400' as const,
    lineHeight:    20,
    letterSpacing: -0.1,
  },
  body: {
    fontFamily:    systemSans,
    fontSize:      15,
    fontWeight:    '400' as const,
    lineHeight:    22,
    letterSpacing: -0.1,
  },
  caption: {
    fontFamily:    systemSans,
    fontSize:      13,
    fontWeight:    '400' as const,
    lineHeight:    18,
    letterSpacing: 0,
  },
  meta: {
    fontFamily:      systemSans,
    fontSize:        12,
    fontWeight:      '400' as const,
    lineHeight:      16,
    letterSpacing:   0.2,
    fontVariant:     ['tabular-nums'] as ('tabular-nums')[],
  },
  metaBold: {
    fontFamily:      systemBold,
    fontSize:        12,
    fontWeight:      '700' as const,
    lineHeight:      16,
    letterSpacing:   0.2,
    fontVariant:     ['tabular-nums'] as ('tabular-nums')[],
  },
  chip: {
    fontFamily:      systemBold,
    fontSize:        11,
    fontWeight:      '700' as const,
    lineHeight:      14,
    letterSpacing:   0.4,
    textTransform:   'uppercase' as const,
  },
} as const;

// Back-compat with existing components that still read Typography.*
export const Typography = {
  displayLg: Type.display,
  bodyMd:    Type.body,
  bodySm:    Type.caption,
  labelSm:   Type.caption,
} as const;

// ─── Motion tokens ───────────────────────────────────────────────────────
// Feed the Reanimated spring/timing configs from here so behavior stays
// consistent across the app. Values come from the motion brief.

export const Motion = {
  spring: {
    cardEnter:  { damping: 22, stiffness: 220, mass: 1 },
    cardExit:   { damping: 22, stiffness: 260 },        // for neighbor collapse
    tab:        { damping: 26, stiffness: 300 },
    sheet:      { damping: 30, stiffness: 380, restDisplacementThreshold: 0.5 },
    quickMenu:  { damping: 24, stiffness: 280 },
  },
  timing: {
    pressIn:    90,
    pressOut:   120,
    exitSwipe:  220,
    tabCross:   160,
    reveal:     240,
    micro:      160,
    skeletonMinHold: 60,
  },
  stagger: 24,
  visibleEnterCap: 5,
  swipe: {
    commitFraction: 0.4,
    commitVelocity: 1200,
    rubberBandAt:   0.6,
  },
} as const;

// ─── Layout constants ────────────────────────────────────────────────────

export const Layout = {
  cardGutter:      Spacing.lg,     // 16 horizontal for text
  cardTopPad:      Spacing.md,     // 12
  cardBottomPad:   Spacing.xl,     // 24 — doubles as separator to next card
  actionIconSize:  22,
  actionRowGap:    Spacing.md,     // 12
  avatarSize:      40,
  avatarSmall:     28,
  headerCollapsedHeight: 60,
  headerExpandedHeight:  132,
  unreadDotSize:   6,
  mediaAspect:     4 / 5,          // Instagram-standard vertical crop
} as const;
