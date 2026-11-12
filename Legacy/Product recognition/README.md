# Legacy Product Recognition UI, Models & Files

This directory contains the disconnected files, CoreML models, and UI components for the **Vision & Product Recognition** feature, archived from the main application target while preserving all code, models, and architecture for future reintroduction.

## Overview of Components

1. **`yolov8n-seg.mlpackage`**
   - YOLOv8 Nano instance segmentation CoreML model.
   - Detects real-time object bounding boxes and masks from camera preview frames for shelf and item localization.

2. **`mobileclip_s2_image_fp16.mlpackage`**
   - Apple MobileCLIP S2 image encoder model (fp16).
   - Generates 512-dimensional visual embedding vectors from cropped product images for similarity matching against inventory.

3. **`MobileSAM-CoreML/` & `MobileSAMService.swift`**
   - Mobile Segment Anything Model (MobileSAM) CoreML encoder and decoder packages.
   - Provides point-prompted or bounding-box-prompted zero-shot foreground object segmentation to cleanly isolate items from complex backgrounds.

4. **`ObjectDetectionService.swift`**
   - Vision CoreML pipeline wrapper executing YOLOv8 segmentation on `CVPixelBuffer` frames.
   - Normalizes coordinates and extracts detected bounding boxes with confidence scores.

5. **`FeatureExtractor.swift`**
   - Handles image pre-processing (resizing, normalization, L2 vector normalization) and runs the MobileCLIP embedding model to output high-accuracy visual fingerprints.

6. **`ProductEmbeddingStore.swift`**
   - SQLite-backed storage (`product_embeddings.sqlite3`) for persisting multiple visual embeddings per inventory item.
   - Computes cosine similarity, k-nearest neighbors, and centroid matching across known items.

7. **`ProductFingerprintManager.swift`**
   - High-level coordinator managing training and real-time inference.
   - Coordinates object detection -> SAM segmentation -> CLIP embedding extraction -> database lookup -> matched item candidates.

8. **`ProductOCRService.swift`**
   - Apple Vision framework OCR service extracting brand names, packaging text, and quantities from localized product regions.

9. **`InventoryCaptureVideoViewController.swift` & `PhotoObjectIsolateViewController`**
   - UI flows for recording multi-angle training video clips or taking item photos when adding new purchases/stock.
   - Auto-extracts sharp keyframes and isolated masks to train new product visual fingerprints into the embedding store.

10. **`SalesScanCameraViewController.swift` (Original Reference)**
    - Snapshot of the full sales scan camera controller before the "Products" segment was disconnected.
    - Contains interactive bounding box overlays, tap-to-confirm candidate lists, and real-time continuous product scanning loops.

---

## How to Reconnect in the Future

If you want to re-enable Vision / Product Recognition:

1. **Move Files Back to App Target**:
   - Move the `.swift` files and `.mlpackage` folders from `Legacy/Product recognition/` back into `B-easy/VisionTab/` (or add them to the Xcode project target membership).

2. **In `AppDelegate.swift`**:
   - Re-enable background embedding initialization:
     ```swift
     ProductFingerprintManager.shared.prepareEmbeddingsForCurrentExtractor()
     ```

3. **In `Main.storyboard` & `SalesScanCameraViewController.swift`**:
   - In `Main.storyboard`, select segmented control `a9L-1p-7BF` and add a segment with title `"Products"` at index 2.
   - In `SalesScanCameraViewController.swift`, re-add `.products` to `SaleScanIntent` and re-enable the product bounding box rendering, tap handlers, and `ProductFingerprintManager` scanning callbacks.

4. **In `AddPurchaseViewController.swift` & `PurchaseItemInformationTableViewController.swift`**:
   - Re-add the "Photo" and "Record" buttons in item detail rows to present `InventoryCaptureVideoViewController` and photo picker for training new item fingerprints.
   - In `savePurchase()`, re-enable `ProductFingerprintManager.shared.updateEmbeddings(forItemID:photos:)`.

