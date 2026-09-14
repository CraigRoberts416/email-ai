import { StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import EmptyState from '@/components/EmptyState';
import { Spacing, Theme, Type } from '@/constants/theme';

// Saved view — conversations the user kept via the card's Save action.
// Saving is local-only until the server ships a saved-conversations table,
// so this renders the empty state and the shell the list will drop into.
export default function Saved() {
  const saved: unknown[] = [];

  return (
    <SafeAreaView style={styles.safe} edges={['top']}>
      <View style={styles.header}>
        <Text style={styles.title}>Saved</Text>
      </View>

      {saved.length === 0 ? (
        <EmptyState
          icon="bookmark"
          title="Nothing saved yet"
          detail="Tap Save on a card to keep it here — receipts, confirmations, anything you'll want again."
        />
      ) : null}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: Theme.bg,
  },
  header: {
    paddingHorizontal: Spacing.lg,
    paddingTop: Spacing.md,
    paddingBottom: Spacing.sm,
  },
  title: {
    ...Type.display,
    fontSize: 28,
    lineHeight: 32,
    color: Theme.textPrimary,
  },
});
