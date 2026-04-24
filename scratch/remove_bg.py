from PIL import Image
import os

def remove_white_background(input_path, output_path, threshold=230):
    """Remove white/near-white background from an image, replacing with transparency."""
    img = Image.open(input_path).convert("RGBA")
    data = img.getdata()
    
    new_data = []
    for item in data:
        # If pixel is near-white (all channels above threshold), make transparent
        if item[0] > threshold and item[1] > threshold and item[2] > threshold:
            new_data.append((255, 255, 255, 0))
        else:
            new_data.append(item)
    
    img.putdata(new_data)
    img.save(output_path, "PNG")
    print(f"  ✓ Saved: {output_path} ({os.path.getsize(output_path) // 1024}KB)")

base = "/Users/apple/Desktop/UiRework/Ledgile Merged/Tabs/Assets.xcassets"

images = [
    (f"{base}/FullWallet.imageset/full_wallet.jpg", f"{base}/FullWallet.imageset/full_wallet.png"),
    (f"{base}/EmptyWallet.imageset/empty_wallet.jpg", f"{base}/EmptyWallet.imageset/empty_wallet.png"),
    (f"{base}/OpenCardbox.imageset/open_cardbox.jpg", f"{base}/OpenCardbox.imageset/open_cardbox.png"),
]

for src, dst in images:
    print(f"Processing: {os.path.basename(src)}")
    remove_white_background(src, dst)
    # Remove the old JPG
    os.remove(src)
    print(f"  ✓ Removed old JPG")

print("\nDone! All 3 images now have transparent backgrounds.")
