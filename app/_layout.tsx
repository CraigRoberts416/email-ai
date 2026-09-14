import { DMSans_400Regular } from '@expo-google-fonts/dm-sans';
import {
  Inter_300Light,
  Inter_400Regular,
  Inter_500Medium,
  useFonts,
} from '@expo-google-fonts/inter';
import { DarkTheme, ThemeProvider } from '@react-navigation/native';
import { Stack, usePathname } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useRef } from 'react';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import 'react-native-reanimated';

import { Observability, startView, stopView } from '@/components/observability';
import { Theme } from '@/constants/theme';
import '@/tasks/backgroundFetch';

SplashScreen.preventAutoHideAsync();

export const unstable_settings = {
  anchor: '(tabs)',
};

// Tracks Expo Router pathname changes as Datadog RUM views.
// Must render inside Observability so the SDK is initialised.
function NavigationTracker() {
  const pathname = usePathname();
  const prevPathnameRef = useRef<string | null>(null);

  useEffect(() => {
    if (prevPathnameRef.current !== null && prevPathnameRef.current !== pathname) {
      stopView(prevPathnameRef.current);
    }
    startView(pathname, pathname);
    prevPathnameRef.current = pathname;
  }, [pathname]);

  return null;
}

// The app is dark-committed. Feed the navigation container the same ground
// color so push transitions never flash white behind a screen.
const navTheme = {
  ...DarkTheme,
  colors: {
    ...DarkTheme.colors,
    background: Theme.bg,
    card:       Theme.bg,
    text:       Theme.textPrimary,
    border:     Theme.border,
    primary:    Theme.accent,
  },
};

export default function RootLayout() {
  const [fontsLoaded] = useFonts({
    Inter_300Light,
    Inter_400Regular,
    Inter_500Medium,
    DMSans_400Regular,
  });

  useEffect(() => {
    if (fontsLoaded) SplashScreen.hideAsync();
  }, [fontsLoaded]);

  if (!fontsLoaded) return null;

  return (
    <GestureHandlerRootView style={{ flex: 1, backgroundColor: Theme.bg }}>
      <Observability>
        <NavigationTracker />
        <ThemeProvider value={navTheme}>
          <Stack screenOptions={{ contentStyle: { backgroundColor: Theme.bg } }}>
            <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
            <Stack.Screen name="email/[messageId]" options={{ headerShown: false }} />
            <Stack.Screen name="modal" options={{ presentation: 'modal', title: 'Modal' }} />
          </Stack>
          <StatusBar style="light" />
        </ThemeProvider>
      </Observability>
    </GestureHandlerRootView>
  );
}
