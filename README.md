# RTS - LS Central

A mobile companion app for LS Central, supporting POS, Mobile Inventory, and Hospitality workflows on Android and iOS.

## Features

- **POS** — Point of Sale operations using username/password authentication
- **Mobile Inventory** — Inventory management via LS Central API
- **Hospitality** — Hospitality module via LS Central API
- **QR Code Setup** — Scan a QR code to configure the connection instead of typing manually

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.41.0 or later)
- Android SDK with command-line tools
- VS Code with the Flutter extension, or Android Studio with the Flutter plugin

### Run the app

```bash
flutter pub get
flutter run
```

## Settings & Connection Setup

The app requires a connection to an LS Central environment. Open **Settings** (gear icon on the home page) to configure.

### Two settings sections

| Section | Used by | Fields |
|---|---|---|
| **API Connection** | Mobile Inventory, Hospitality | On-Premise: Server, Port, Instance, Company. SaaS: Tenant ID, Client ID, Client Secret, Company |
| **POS Login** | POS only | Username, Password |

### Manual setup

1. Tap the **gear icon** on the home page
2. Tap **Setup Manually**
3. Choose **On-Premise** or **SaaS**
4. Fill in the required fields and tap **Save**
5. Tap the **edit icon** on the POS Login card to add POS credentials

### QR Code setup

Instead of typing manually, you can scan a QR code containing the connection details as JSON.

1. Tap the **gear icon** on the home page
2. Tap **Scan QR Code** (or the scanner icon in the top-right)
3. Point your camera at the QR code

#### QR Code JSON format

The QR code must contain a JSON string with the following fields:

**SaaS example:**

```json
{
  "type": "saas",
  "tenant": "contoso.onmicrosoft.com",
  "clientId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "clientSecret": "your-client-secret",
  "company": "CRONUS International Ltd.",
  "posUsername": "cashier1",
  "posPassword": "password123"
}
```

**On-Premise example:**

```json
{
  "type": "onPremise",
  "serverUrl": "192.168.1.100",
  "port": 7048,
  "instance": "BC250",
  "company": "CRONUS International Ltd.",
  "posUsername": "cashier1",
  "posPassword": "password123"
}
```

#### Field reference

| Field | Required | Description |
|---|---|---|
| `type` | Yes | `"saas"` or `"onPremise"` |
| `tenant` | SaaS only | Azure AD tenant ID |
| `clientId` | SaaS only | Azure AD app client ID |
| `clientSecret` | SaaS only | Azure AD app client secret |
| `serverUrl` | On-Premise only | Server address or hostname |
| `port` | On-Premise only | OData port (default: 7048) |
| `instance` | On-Premise only | BC server instance name |
| `company` | Optional | Company name in Business Central |
| `posUsername` | Optional | POS operator username |
| `posPassword` | Optional | POS operator password |

If `posUsername` and `posPassword` are omitted from the QR code, existing POS credentials are preserved.
