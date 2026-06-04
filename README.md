# B-easy 📱

<div align="center">
  <img src="https://img.shields.io/badge/Platform-iOS-blue.svg?style=flat-square" alt="Platform: iOS" />
  <img src="https://img.shields.io/badge/Language-Swift-orange.svg?style=flat-square" alt="Language: Swift" />
  <img src="https://img.shields.io/badge/License-MIT-green.svg?style=flat-square" alt="License: MIT" />
  <img src="https://img.shields.io/badge/Architecture-MVC-purple.svg?style=flat-square" alt="Architecture" />
</div>

<br/>

**B-easy** is a next-generation, AI-first ledger and inventory management iOS application designed specifically for modern shopkeepers and retailers. It streamlines daily retail operations through state-of-the-art on-device machine learning, voice commerce, and intelligent visual scanning.

---

## 🚀 Key Features

### 🎙️ Voice-Powered Commerce (AI)
- **Voice Sales & Purchase Entry**: Simply speak to record transactions. Powered by highly optimized, on-device ML models (Whisper, MiniLM) to transcribe and extract intent instantly.
- **Natural Language Parsing**: Automatically matches spoken items to inventory.

### 📸 Intelligent Vision & OCR
- **Bill & Invoice Scanning**: Instantly digitize physical bills. Powered by on-device YOLOv8 segmentation and CoreML text recognition to extract items, prices, and tax data.
- **Visual Inventory Search**: Find products using image embeddings (MobileCLIP).

### 📦 Smart Stock Management
- **Real-Time Inventory Tracking**: Monitor stock levels, low-stock alerts, and expiration dates.
- **Categorization & Profiling**: Comprehensive item profiles with detailed metadata and purchase history.

### 🧾 Comprehensive GST Compliance
- **Automated Tax Calculations**: Built-in logic for CGST, SGST, and IGST.
- **HSN Code Autocomplete**: Smart prediction of harmonized system nomenclature for seamless compliance.
- **GST Returns**: Automated report generation and formatting.

### 📊 Advanced Dashboard & Analytics
- **Financial Insights**: Real-time sales charts, credit reports, and recent transaction monitoring.
- **Local-First Architecture**: Fast, offline-capable interactions utilizing efficient SQLite databases and intelligent caching architectures.

---

## 🛠️ Technology Stack

- **Platform**: iOS 15.0+
- **Language**: Swift 5
- **UI Framework**: UIKit (with programmatic + XIB-based layouts)
- **Machine Learning**: CoreML, Whisper (ggml), YOLOv8, MobileCLIP
- **Local Storage**: SQLite
- **Dependency Management**: CocoaPods / Swift Package Manager

---

## 📂 Project Structure

```text
Ledgile/
├── Tabs/
│   ├── DashboardTab/      # Main analytics, charts, and top-level reporting
│   ├── SalesTab/          # Point of sale, voice entry, and transaction creation
│   ├── StockTab/          # Inventory management, purchases, and expiration tracking
│   ├── VisionTab/         # OCR, barcode scanning, and object detection services
│   ├── User Profile/      # Settings, GST configurations, and user details
│   ├── Search Tab/        # Global search functionalities
│   ├── Models/            # Core data structures and business logic
│   └── Tabs_Models/       # Pre-compiled ML models (.mlmodelc / .mlpackage)
└── ...
```

---

## ⚙️ Setup & Installation

1. **Clone the Repository**
   ```bash
   git clone https://github.com/Souravgupta2111/Ledgile.git
   cd Ledgile
   ```

2. **Git LFS (Large File Storage)**
   This project uses Git LFS to track machine learning models (`*.bin`, `*.mlmodelc`). Ensure Git LFS is installed and pull the required files:
   ```bash
   git lfs install
   git lfs pull
   ```

3. **Open the Project**
   Open `Tabs.xcodeproj` (or `.xcworkspace` if using CocoaPods) in Xcode.

4. **Build and Run**
   Select your target simulator or physical device and hit `Cmd + R`.

---

## 🔒 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

<div align="center">
  <i>Designed and engineered for the modern retail ecosystem.</i>
</div>
