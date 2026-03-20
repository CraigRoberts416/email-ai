# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
npm start           # Start Expo dev server (interactive: choose Android/iOS/Web)
npm run ios         # Run on iOS simulator
npm run android     # Run on Android emulator
npm run web         # Run in browser
npm run lint        # Run ESLint
npm run reset-project  # Archive current app/ to app-example/, reset to blank slate
```

No test framework is configured.

## Architecture

This is an **Expo Router** React Native app targeting iOS, Android, and web from a single TypeScript codebase.

### Routing

File-based routing via Expo Router. `app/` maps directly to routes:
- `app/(tabs)/` — bottom tab navigator (Home/Inbox, Explore)
- `app/_layout.tsx` — root stack with theme provider
- `app/(tabs)/_layout.tsx` — tab bar config (icons, haptics, colors)

### Theme System

`constants/theme.ts` exports `Colors` (light/dark palettes) and `Fonts` (platform-specific font families). Components consume these via the `useThemeColor` hook (`hooks/use-theme-color.ts`). Platform-specific hook implementations use file-extension overrides (e.g., `use-color-scheme.web.ts`).

`ThemedText` and `ThemedView` are the base building blocks for all theme-aware UI.

### Platform-Specific Code

Use file extensions for platform variants:
- `.ios.tsx` — iOS only (e.g., `icon-symbol.ios.tsx` uses SF Symbols)
- `.web.ts` — Web only (e.g., `use-color-scheme.web.ts`)
- Default file is the Android/fallback implementation

### Icons

`components/ui/icon-symbol.tsx` is the cross-platform icon wrapper. iOS uses SF Symbols (native), Android/Web fall back to `@expo/vector-icons` MaterialIcons.

### Path Aliases

`@/*` maps to the repo root (configured in `tsconfig.json`). Use `@/components/...`, `@/constants/...`, `@/hooks/...` for imports.

### Key Config

- `app.json` — Expo config: new architecture enabled, React Compiler enabled, typed routes enabled
- `tsconfig.json` — strict TypeScript, extends `expo/tsconfig.base`
