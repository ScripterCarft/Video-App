import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { SubscriptionsScreen } from '../screens/SubscriptionsScreen';
import { useStrings } from '../i18n/strings';

const Stack = createNativeStackNavigator();

export function SubscriptionsStack() {
  const strings = useStrings();

  return (
    <Stack.Navigator
      screenOptions={{
        unstable_headerRightItems: () => [
          {
            type: 'button',
            label: strings.profile.open,
            icon: { type: 'sfSymbol', name: 'person.crop.circle.fill' },
            onPress: () => {},
          },
        ],
      }}
    >
      <Stack.Screen
        name="Subscriptions"
        component={SubscriptionsScreen}
        options={{ title: strings.tabs.subscriptions, headerLargeTitle: true }}
      />
    </Stack.Navigator>
  );
}
