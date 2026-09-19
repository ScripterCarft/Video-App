import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { SearchScreen } from '../screens/SearchScreen';
import { useStrings } from '../i18n/strings';
import { ProfileButton } from '../components/ProfileButton';

const Stack = createNativeStackNavigator();

export function SearchStack() {
  const strings = useStrings();

  return (
    <Stack.Navigator screenOptions={{ headerRight: () => <ProfileButton /> }}>
      <Stack.Screen
        name="Search"
        component={SearchScreen}
        options={{ title: strings.tabs.search, headerLargeTitle: true }}
      />
    </Stack.Navigator>
  );
}
