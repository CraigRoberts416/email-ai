import { Tabs } from 'expo-router';
import { StyleSheet } from 'react-native';

import { HapticTab } from '@/components/haptic-tab';
import { IconSymbol } from '@/components/ui/icon-symbol';
import { Theme, Type } from '@/constants/theme';

export default function TabLayout() {
  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarButton: HapticTab,
        tabBarActiveTintColor:   Theme.textPrimary,
        tabBarInactiveTintColor: Theme.textTertiary,
        tabBarStyle: {
          backgroundColor: Theme.bg,
          borderTopColor:  Theme.border,
          borderTopWidth:  StyleSheet.hairlineWidth,
        },
        tabBarLabelStyle: {
          ...Type.meta,
          letterSpacing: 0.1,
        },
      }}>
      <Tabs.Screen
        name="index"
        options={{
          title: 'Feed',
          tabBarIcon: ({ color }) => <IconSymbol size={24} name="house" color={color} />,
        }}
      />
      <Tabs.Screen
        name="explore"
        options={{
          title: 'Saved',
          tabBarIcon: ({ color }) => <IconSymbol size={24} name="bookmark" color={color} />,
        }}
      />
    </Tabs>
  );
}
