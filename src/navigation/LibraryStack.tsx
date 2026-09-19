import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { LibraryScreen } from '../screens/LibraryScreen';
import { useStrings } from '../i18n/strings';

const Stack = createNativeStackNavigator();

export function LibraryStack() {
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
        name="Library"
        component={LibraryScreen}
        options={{ title: strings.tabs.library, headerLargeTitleEnabled: true }}
      />
    </Stack.Navigator>
  );
}
