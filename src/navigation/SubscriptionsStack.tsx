import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { SubscriptionsScreen } from '../screens/SubscriptionsScreen';
import { useStrings } from '../i18n/strings';
import { ProfileButton } from '../components/ProfileButton';

const Stack = createNativeStackNavigator();

export function SubscriptionsStack() {
  const strings = useStrings();

  return (
    <Stack.Navigator screenOptions={{ headerRight: () => <ProfileButton /> }}>
      <Stack.Screen
        name="Subscriptions"
        component={SubscriptionsScreen}
        options={{ title: strings.tabs.subscriptions, headerLargeTitle: true }}
      />
    </Stack.Navigator>
  );
}
