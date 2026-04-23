import { Text, View } from 'react-native';

export default function TestScreen() {
  return (
    <View style={{ flex: 1, backgroundColor: 'red', justifyContent: 'center', alignItems: 'center' }}>
      <Text style={{ color: 'white', fontSize: 32 }}>NAVIGATION WORKED</Text>
    </View>
  );
}
