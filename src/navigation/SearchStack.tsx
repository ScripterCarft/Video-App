import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { SearchScreen } from '../screens/SearchScreen';
import { useStrings } from '../i18n/strings';

const Stack = createNativeStackNavigator();

export function SearchStack() {
  const strings = useStrings();

  return (
    <Stack.Navigator>
      <Stack.Screen
        name="Search"
        component={SearchScreen}
        options={{ title: strings.tabs.search, headerLargeTitleEnabled: true }}
      />
    </Stack.Navigator>
  );
}
