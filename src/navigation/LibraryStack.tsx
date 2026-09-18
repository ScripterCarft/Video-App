import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { LibraryScreen } from '../screens/LibraryScreen';

const Stack = createNativeStackNavigator();

export function LibraryStack() {
  return (
    <Stack.Navigator>
      <Stack.Screen
        name="Library"
        component={LibraryScreen}
        options={{ title: 'Mediathek', headerLargeTitle: true }}
      />
    </Stack.Navigator>
  );
}
