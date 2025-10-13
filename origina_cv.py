# Import necessary libraries
import os
import pandas as pd
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw, ImageFont

# ---------------------------------------------------------------------------
# 1. DEFINE PATHS
# ---------------------------------------------------------------------------
# !!! UPDATED FOR NEW LOCATION !!!
# Path updated to new location: ~/Documents/VOC2012_train_val
shared_folder_path = os.path.expanduser('~/Documents')

# Define the path to the Pascal VOC 2012 dataset root
# Structure: ~/Documents/VOC2012_train_val/VOC2012_train_val/
voc_root = os.path.join(shared_folder_path, 'VOC2012_train_val', 'VOC2012_train_val')

annotations_dir = os.path.join(voc_root, 'Annotations')
images_dir = os.path.join(voc_root, 'JPEGImages')

# ---------------------------------------------------------------------------
# 2. PARSE XML ANNOTATIONS AND CREATE A DATAFRAME
# ---------------------------------------------------------------------------
def parse_voc_annotations(annotations_dir):
    """Parses all XML files in the Annotations directory."""
    xml_data = []
    # Loop through every annotation file
    for xml_file in os.listdir(annotations_dir):
        if not xml_file.endswith('.xml'):
            continue
        
        tree = ET.parse(os.path.join(annotations_dir, xml_file))
        root = tree.getroot()
        
        image_name = root.find('filename').text
        
        # Find every object in the image
        for obj in root.findall('object'):
            label = obj.find('name').text
            bbox = obj.find('bndbox')
            # Get bounding box coordinates - FIXED to handle floating-point values
            xmin = int(float(bbox.find('xmin').text))
            ymin = int(float(bbox.find('ymin').text))
            xmax = int(float(bbox.find('xmax').text))
            ymax = int(float(bbox.find('ymax').text))
            
            xml_data.append({
                'image_name': image_name,
                'label': label,
                'xmin': xmin,
                'ymin': ymin,
                'xmax': xmax,
                'ymax': ymax
            })
    # Return a pandas DataFrame
    return pd.DataFrame(xml_data)

print(f"Parsing annotations from: {annotations_dir}")
try:
    # Create the DataFrame
    voc_df = parse_voc_annotations(annotations_dir)
    print("Successfully parsed all annotations.")
    print("Here are the first 5 entries in the DataFrame:")
    display(voc_df.head())
except FileNotFoundError:
    print(f"ERROR: Directory not found at '{annotations_dir}'.")
    print("Please check that the 'shared_folder_path' is correct and that the VOC dataset has the standard 'VOCdevkit/VOC2012' structure.")

print("-" * 50)

# ---------------------------------------------------------------------------
# 3. VISUALIZE A SAMPLE IMAGE WITH ITS BOUNDING BOXES
# ---------------------------------------------------------------------------
def visualize_image(image_name, dataframe):
    """Draws bounding boxes on a given image."""
    # Get the full path to the image
    img_path = os.path.join(images_dir, image_name)
    
    # Open the image
    img = Image.open(img_path).convert("RGB")
    draw = ImageDraw.Draw(img)
    
    # Get all annotations for this specific image
    image_annotations = dataframe[dataframe['image_name'] == image_name]
    
    # Draw a rectangle and label for each object
    for _, row in image_annotations.iterrows():
        box = [row['xmin'], row['ymin'], row['xmax'], row['ymax']]
        draw.rectangle(box, outline="red", width=3)
        
        # Optional: Add text label
        # You might need to install a font or provide a path to a .ttf file
        # draw.text((row['xmin'], row['ymin']), row['label'], fill="red")

    print(f"Displaying image '{image_name}' with its bounding boxes:")
    display(img)

# Visualize a random image from the dataset
if 'voc_df' in locals() and not voc_df.empty:
    sample_image = voc_df['image_name'].sample(1).iloc[0]
    visualize_image(sample_image, voc_df)

# --- SANITY CHECK CODE ---
# Add this to your notebook to debug the path
print(f"Checking for annotations folder at: {annotations_dir}")

if not os.path.exists(annotations_dir):
    print("\n---> ERROR: This directory does not exist!")
    print("Please double-check your 'shared_folder_path' and 'voc2012_test' folder name.")
else:
    print("\n---> SUCCESS: Directory found!")
    try:
        # List the first 5 files to ensure they are XML files
        first_five_files = os.listdir(annotations_dir)[:5]
        print("Here are the first 5 files found in this directory:")
        print(first_five_files)
        if not any(f.endswith('.xml') for f in first_five_files):
             print("\nWARNING: Did not find any .xml files here. Is this the correct 'Annotations' folder?")
    except Exception as e:
        print(f"Could not read directory contents. Error: {e}")

# --- END OF SANITY CHECK ---