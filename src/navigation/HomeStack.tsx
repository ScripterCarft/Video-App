import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { HomeScreen } from '../screens/HomeScreen';
import { useStrings } from '../i18n/strings';

const Stack = createNativeStackNavigator();

export function HomeStack() {
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
        name="Home"
        component={HomeScreen}
        options={{ title: strings.tabs.home, headerLargeTitleEnabled: true }}
      />
    </Stack.Navigator>
  );
}
