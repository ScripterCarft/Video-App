import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { SubscriptionsScreen } from '../screens/SubscriptionsScreen';

const Stack = createNativeStackNavigator();

export function SubscriptionsStack() {
  return (
    <Stack.Navigator>
      <Stack.Screen
        name="Subscriptions"
        component={SubscriptionsScreen}
        options={{ title: 'Abos', headerLargeTitle: true }}
      />
    </Stack.Navigator>
  );
}
