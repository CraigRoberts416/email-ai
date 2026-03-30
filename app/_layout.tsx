import {
  Inter_300Light,
  Inter_400Regular,
  Inter_500Medium,
  useFonts,
} from '@expo-google-fonts/inter';
import { DarkTheme, DefaultTheme, ThemeProvider } from '@react-navigation/native';
import {
  BatchSize,
  DatadogProvider,
  DatadogProviderConfiguration,
  DdRum,
  SdkVerbosity,
  TrackingConsent,
  UploadFrequency,
} from '@datadog/mobile-react-native';
import {
  ImagePrivacyLevel,
  SessionReplay,
  TextAndInputPrivacyLevel,
  TouchPrivacyLevel,
} from '@datadog/mobile-react-native-session-replay';
import { Stack, usePathname } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useRef } from 'react';
import 'react-native-reanimated';

import { useColorScheme } from '@/hooks/use-color-scheme';

const datadogConfig = new DatadogProviderConfiguration(
  'pub83419a0f322102997f55f5342d1a8635',
  'prod',
  TrackingConsent.GRANTED,
  {
    rumConfiguration: {
      applicationId: 'dcea72ee-32a7-4eff-97b6-72501fdbdf9c',
      trackInteractions: true,  // auto-tracks TouchableOpacity / Pressable taps by label
      trackResources: true,
      trackErrors: true,
      nativeCrashReportEnabled: true,
      sessionSampleRate: 100,
      longTaskThresholdMs: 100,  // JS tasks > 100ms flagged as long tasks / hangs
    },
    logsConfiguration: {},
    traceConfiguration: {},
  }
);
datadogConfig.site = 'US5';

if (__DEV__) {
  datadogConfig.uploadFrequency = UploadFrequency.FREQUENT;
  datadogConfig.batchSize = BatchSize.SMALL;
  datadogConfig.verbosity = SdkVerbosity.DEBUG;
}

SplashScreen.preventAutoHideAsync();

export const unstable_settings = {
  anchor: '(tabs)',
};

// Tracks Expo Router pathname changes as Datadog RUM views.
// Must be rendered inside DatadogProvider so the SDK is initialised.
function NavigationTracker() {
  const pathname = usePathname();
  const prevPathnameRef = useRef<string | null>(null);

  useEffect(() => {
    if (prevPathnameRef.current !== null && prevPathnameRef.current !== pathname) {
      DdRum.stopView(prevPathnameRef.current);
    }
    DdRum.startView(pathname, pathname);
    prevPathnameRef.current = pathname;
  }, [pathname]);

  return null;
}

// Enables Session Replay once the Datadog SDK is ready.
// Must be rendered inside DatadogProvider.
// Privacy: touches visible, text unmasked except password fields, all images visible.
function SessionReplayConfigure() {
  useEffect(() => {
    SessionReplay.enable({
      replaySampleRate: 100,
      touchPrivacyLevel: TouchPrivacyLevel.SHOW,
      textAndInputPrivacyLevel: TextAndInputPrivacyLevel.MASK_SENSITIVE_INPUTS,
      imagePrivacyLevel: ImagePrivacyLevel.MASK_NONE,
    }).catch(e => console.warn('[datadog] session replay init failed:', e));
  }, []);
  return null;
}

export default function RootLayout() {
  const colorScheme = useColorScheme();
  const [fontsLoaded] = useFonts({
    Inter_300Light,
    Inter_400Regular,
    Inter_500Medium,
  });

  useEffect(() => {
    if (fontsLoaded) SplashScreen.hideAsync();
  }, [fontsLoaded]);

  if (!fontsLoaded) return null;

  return (
    <DatadogProvider configuration={datadogConfig}>
      <SessionReplayConfigure />
      <NavigationTracker />
      <ThemeProvider value={colorScheme === 'dark' ? DarkTheme : DefaultTheme}>
        <Stack>
          <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
          <Stack.Screen name="modal" options={{ presentation: 'modal', title: 'Modal' }} />
        </Stack>
        <StatusBar style="auto" />
      </ThemeProvider>
    </DatadogProvider>
  );
}
