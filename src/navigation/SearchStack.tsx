import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { SearchScreen } from '../screens/SearchScreen';

const Stack = createNativeStackNavigator();

export function SearchStack() {
  return (
    <Stack.Navigator>
      <Stack.Screen
        name="Search"
        component={SearchScreen}
        options={{ title: 'Suchen', headerLargeTitle: true }}
      />
    </Stack.Navigator>
  );
}
