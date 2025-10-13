import os
import pandas as pd
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw
import matplotlib.pyplot as plt

def parse_voc_annotations(annotations_dir):
    """Parse VOC XML annotation files with robust coordinate handling."""
    
    annotations = []
    
    for xml_file in os.listdir(annotations_dir):
        if xml_file.endswith('.xml'):
            xml_path = os.path.join(annotations_dir, xml_file)
            tree = ET.parse(xml_path)
            root = tree.getroot()
            
            # Extract basic info
            filename = root.find('filename').text
            size = root.find('size')
            width = int(size.find('width').text)
            height = int(size.find('height').text)
            
            # Extract object annotations
            for obj in root.findall('object'):
                class_name = obj.find('name').text
                bbox = obj.find('bndbox')
                
                # CRITICAL FIX: Handle floating-point coordinates
                xmin = int(float(bbox.find('xmin').text))
                ymin = int(float(bbox.find('ymin').text))
                xmax = int(float(bbox.find('xmax').text))
                ymax = int(float(bbox.find('ymax').text))
                
                annotations.append({
                    'filename': filename,
                    'width': width,
                    'height': height,
                    'class': class_name,
                    'xmin': xmin,
                    'ymin': ymin,
                    'xmax': xmax,
                    'ymax': ymax
                })
    
    return pd.DataFrame(annotations)

def visualize_image(image_path, annotations, filename):
    """Visualize an image with its bounding box annotations."""
    
    # Filter annotations for this image
    img_annotations = annotations[annotations['filename'] == filename]
    
    if img_annotations.empty:
        print(f"No annotations found for {filename}")
        return
        
    # Load and display image
    image = Image.open(image_path)
    draw = ImageDraw.Draw(image)
    
    # Draw bounding boxes
    for _, ann in img_annotations.iterrows():
        bbox = [ann['xmin'], ann['ymin'], ann['xmax'], ann['ymax']]
        draw.rectangle(bbox, outline='red', width=2)
        draw.text((ann['xmin'], ann['ymin'] - 10), ann['class'], fill='red')
    
    # Display using matplotlib for Jupyter compatibility
    plt.figure(figsize=(12, 8))
    plt.imshow(image)
    plt.axis('off')
    plt.title(f'Image: {filename}')
    plt.show()

def auto_find_voc_dataset():
    """Auto-detect VOC dataset location based on environment."""
    possible_paths = [
        # Remote server E4S container path (WORKING PATH CONFIRMED)
        '/opt/hccs_shared/Share/VOC2012_train_val/VOC2012_train_val',
        # Alternative paths to check
        '/opt/hccs_shared/Share/VOC2012_train_val',
        '/SharedContent/LocalShare/VOC2012_train_val',
        '/home/hccsadmin1/SharedContent/LocalShare/VOC2012_train_val',
        # Local development paths
        './VOC2012_train_val',
        '../VOC2012_train_val',
        './data/VOC2012_train_val'
    ]
    
    for path in possible_paths:
        if os.path.exists(path):
            # Check if it has the proper structure
            annotations_path = os.path.join(path, 'Annotations')
            images_path = os.path.join(path, 'JPEGImages')
            
            if os.path.exists(annotations_path) and os.path.exists(images_path):
                return path
    
    return None

if __name__ == "__main__":
    # Auto-detect dataset location
    voc_path = auto_find_voc_dataset()
    
    if voc_path is None:
        print("❌ VOC dataset not found in any expected location")
        print("Please ensure you're running this in the correct environment:")
        print("- For remote server: inside E4S Singularity container")
        print("- For local: place VOC dataset in current directory")
        exit(1)
    
    annotations_dir = os.path.join(voc_path, 'Annotations')
    images_dir = os.path.join(voc_path, 'JPEGImages')
    
    print(f"✅ VOC Dataset found at: {voc_path}")
    print(f"Annotations: {annotations_dir}")
    print(f"Images: {images_dir}")
    
    # Parse all annotations
    print("\nLoading VOC annotations...")
    df = parse_voc_annotations(annotations_dir)
    
    print(f"\n✅ Dataset loaded successfully!")
    print(f"Total annotations: {len(df)}")
    print(f"Unique images: {df['filename'].nunique()}")
    print(f"Unique classes: {df['class'].nunique()}")
    
    # Show class distribution
    print("\nClass distribution:")
    print(df['class'].value_counts())
    
    # Example visualization
    sample_filename = df['filename'].iloc[0]
    sample_image_path = os.path.join(images_dir, sample_filename)
    
    if os.path.exists(sample_image_path):
        print(f"\nVisualizing sample image: {sample_filename}")
        visualize_image(sample_image_path, df, sample_filename)
    else:
        print(f"\nImage file not found: {sample_image_path}")