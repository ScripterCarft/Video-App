import { PlatformColor, StyleSheet, View } from 'react-native';

export function HomeScreen() {
  return <View style={styles.container} />;
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: PlatformColor('systemBackground'),
  },
});
