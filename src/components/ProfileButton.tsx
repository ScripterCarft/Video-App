import { Pressable, StyleSheet } from 'react-native';
import { SymbolView } from 'expo-symbols';

export function ProfileButton() {
  return (
    <Pressable hitSlop={8} style={styles.button}>
      <SymbolView name="person.crop.circle.fill" size={28} tintColor="#8E8E93" />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  button: {
    marginRight: 4,
  },
});
