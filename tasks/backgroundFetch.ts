import AsyncStorage from '@react-native-async-storage/async-storage';
import * as BackgroundFetch from 'expo-background-fetch';
import * as SecureStore from 'expo-secure-store';
import * as TaskManager from 'expo-task-manager';

export const BACKGROUND_FETCH_TASK = 'background-fetch-feed';

const FEED_BASE_URL = process.env.EXPO_PUBLIC_FEED_BASE_URL || 'https://email-ai-server.onrender.com';
const AUTH_STORAGE_KEY = 'gmail_auth';

TaskManager.defineTask(BACKGROUND_FETCH_TASK, async () => {
  try {
    const raw = await SecureStore.getItemAsync(AUTH_STORAGE_KEY);
    if (!raw) return BackgroundFetch.BackgroundFetchResult.NoData;

    const { accessToken } = JSON.parse(raw);
    if (!accessToken) return BackgroundFetch.BackgroundFetchResult.NoData;

    const res = await fetch(`${FEED_BASE_URL}/feed`, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (!res.ok) return BackgroundFetch.BackgroundFetchResult.Failed;

    const { cards } = await res.json();
    await AsyncStorage.setItem('feed_cache', JSON.stringify(cards));
    return BackgroundFetch.BackgroundFetchResult.NewData;
  } catch {
    return BackgroundFetch.BackgroundFetchResult.Failed;
  }
});

export async function registerBackgroundFetch() {
  const status = await BackgroundFetch.getStatusAsync();
  if (
    status === BackgroundFetch.BackgroundFetchStatus.Restricted ||
    status === BackgroundFetch.BackgroundFetchStatus.Denied
  ) {
    return;
  }

  const isRegistered = await TaskManager.isTaskRegisteredAsync(BACKGROUND_FETCH_TASK);
  if (!isRegistered) {
    await BackgroundFetch.registerTaskAsync(BACKGROUND_FETCH_TASK, {
      minimumInterval: 15 * 60,
      stopOnTerminate: false,
      startOnBoot: true,
    });
  }
}
