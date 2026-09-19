import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { LibraryScreen } from '../screens/LibraryScreen';
import { useStrings } from '../i18n/strings';
import { ProfileButton } from '../components/ProfileButton';

const Stack = createNativeStackNavigator();

export function LibraryStack() {
  const strings = useStrings();

  return (
    <Stack.Navigator screenOptions={{ headerRight: () => <ProfileButton /> }}>
      <Stack.Screen
        name="Library"
        component={LibraryScreen}
        options={{ title: strings.tabs.library, headerLargeTitle: true }}
      />
    </Stack.Navigator>
  );
}
