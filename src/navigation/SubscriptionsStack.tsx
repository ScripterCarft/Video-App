import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { SubscriptionsScreen } from '../screens/SubscriptionsScreen';
import { useStrings } from '../i18n/strings';

const Stack = createNativeStackNavigator();

export function SubscriptionsStack() {
  const strings = useStrings();

  return (
    <Stack.Navigator>
      <Stack.Screen
        name="Subscriptions"
        component={SubscriptionsScreen}
        options={{
          title: strings.tabs.subscriptions,
          headerLargeTitleEnabled: true,
          headerTransparent: true,
        }}
      />
    </Stack.Navigator>
  );
}
