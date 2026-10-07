import os
from PIL import Image

def generate_icons():
    repo_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    source_img_path = r"C:\Users\User 1\.gemini\antigravity-ide\brain\bfa8f343-60e9-4338-acc7-4b486fc993f1\.user_uploaded\media_1790831435561.jpg"

    print("Opening source logo...")
    img = Image.open(source_img_path)

    # Emblem bounding box: (383, 38, 638, 293)
    crop = img.crop((383, 38, 638, 293))
    w, h = crop.size
    crop_hd = crop.resize((w * 4, h * 4), Image.Resampling.LANCZOS).convert('RGBA')

    pix = crop_hd.load()
    hw, hh = crop_hd.size

    for y in range(hh):
        for x in range(hw):
            r, g, b, a = pix[x, y]
            val = max(r, g, b)
            if val < 20:
                pix[x, y] = (255, 255, 255, 0)
            elif val < 45 and (r > g + 10 or b > g + 10 or g > r + 10):
                alpha = int(min(255, (val - 15) * (255.0 / 30.0)))
                pix[x, y] = (r, g, b, alpha)
            elif val < 38:
                alpha = int(min(255, (val - 15) * (255.0 / 23.0)))
                pix[x, y] = (r, g, b, alpha)
            else:
                pix[x, y] = (r, g, b, 255)

    # Master 1024x1024 canvas with pure white background
    master_1024 = Image.new('RGB', (1024, 1024), (255, 255, 255))
    emblem_1024 = crop_hd.resize((800, 800), Image.Resampling.LANCZOS)
    master_1024.paste(emblem_1024, (112, 112), emblem_1024)

    # 1. Save master icon-512.png in repo root (used by flutter_launcher_icons)
    icon_512 = master_1024.resize((512, 512), Image.Resampling.LANCZOS)
    icon_512.save(os.path.join(repo_dir, "icon-512.png"))
    print("Saved icon-512.png in repo root")

    # 2. Save in assets/
    os.makedirs(os.path.join(repo_dir, "assets"), exist_ok=True)
    icon_512.save(os.path.join(repo_dir, "assets", "icon-512.png"))
    master_1024.save(os.path.join(repo_dir, "assets", "app_icon.png"))
    print("Saved assets/icon-512.png and assets/app_icon.png")

    # 3. Android mipmap directories
    android_res = os.path.join(repo_dir, "android", "app", "src", "main", "res")
    android_sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, size in android_sizes.items():
        dir_path = os.path.join(android_res, folder)
        os.makedirs(dir_path, exist_ok=True)
        resized = master_1024.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(os.path.join(dir_path, "launcher_icon.png"))
        resized.save(os.path.join(dir_path, "ic_launcher.png"))
        print(f"Saved Android {folder} ({size}x{size})")

    # 4. iOS icons
    ios_icon_dir = os.path.join(repo_dir, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    if os.path.exists(ios_icon_dir):
        for f in os.listdir(ios_icon_dir):
            if f.endswith(".png"):
                target = os.path.join(ios_icon_dir, f)
                try:
                    with Image.open(target) as existing:
                        target_size = existing.size
                    ios_resized = master_1024.resize(target_size, Image.Resampling.LANCZOS)
                    ios_resized.save(target)
                except Exception as e:
                    print(f"Warning iOS icon {f}: {e}")
        print("Updated all iOS AppIcon set")

    # 5. macOS icons
    macos_icon_dir = os.path.join(repo_dir, "macos", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    if os.path.exists(macos_icon_dir):
        for f in os.listdir(macos_icon_dir):
            if f.endswith(".png"):
                target = os.path.join(macos_icon_dir, f)
                try:
                    with Image.open(target) as existing:
                        target_size = existing.size
                    macos_resized = master_1024.resize(target_size, Image.Resampling.LANCZOS)
                    macos_resized.save(target)
                except Exception as e:
                    print(f"Warning macOS icon {f}: {e}")
        print("Updated all macOS AppIcon set")

    # 6. Web and Simulator
    web_icons_dir = os.path.join(repo_dir, "web", "icons")
    if os.path.exists(web_icons_dir):
        master_1024.resize((192, 192), Image.Resampling.LANCZOS).save(os.path.join(web_icons_dir, "Icon-192.png"))
        master_1024.resize((512, 512), Image.Resampling.LANCZOS).save(os.path.join(web_icons_dir, "Icon-512.png"))
        master_1024.resize((192, 192), Image.Resampling.LANCZOS).save(os.path.join(web_icons_dir, "Icon-maskable-192.png"))
        master_1024.resize((512, 512), Image.Resampling.LANCZOS).save(os.path.join(web_icons_dir, "Icon-maskable-512.png"))
    
    web_favicon = os.path.join(repo_dir, "web", "favicon.png")
    master_1024.resize((32, 32), Image.Resampling.LANCZOS).save(web_favicon)

    sim_dir = os.path.join(repo_dir, "web_simulator")
    if os.path.exists(sim_dir):
        master_1024.resize((192, 192), Image.Resampling.LANCZOS).save(os.path.join(sim_dir, "icon-192.png"))
        master_1024.resize((512, 512), Image.Resampling.LANCZOS).save(os.path.join(sim_dir, "icon-512.png"))
        master_1024.resize((512, 512), Image.Resampling.LANCZOS).save(os.path.join(sim_dir, "mcp-icon-512.png"))
        print("Updated web simulator icons")

    print("\nALL PLATFORM ICONS SUCCESSFULLY GENERATED ON PURE WHITE BACKGROUND!")

if __name__ == "__main__":
    generate_icons()
