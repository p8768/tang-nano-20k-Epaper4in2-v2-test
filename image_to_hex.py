from PIL import Image
import numpy as np

def image_to_hex(input_image_path, output_hex_path, width, height):
    # Открываем изображение и преобразуем в монохромное
    img = Image.open(input_image_path).convert('L')
    
    # Изменяем размер (если нужно)
    if img.size != (width, height):
        img = img.resize((width, height))
    
    # Преобразуем в numpy array
    img_array = np.array(img)
    
    # Бинаризация (если нужно, можно настроить порог)
    threshold = 128
    binary_array = (img_array > threshold).astype(np.uint8)
    
    # Преобразуем в формат для EPD (1 бит на пиксель)
    # Создаем буфер нужного размера (width * height / 8)
    buffer_size = (width // 8) * height
    epd_buffer = np.zeros(buffer_size, dtype=np.uint8)
    
    # Заполняем буфер
    for y in range(height):
        for x in range(0, width, 8):
            byte = 0
            for bit in range(8):
                if x + bit < width:
                    pixel = binary_array[y, x + bit]
                    byte |= (pixel << (7 - bit))
            epd_buffer[(y * (width // 8)) + (x // 8)] = byte
    
    # Сохраняем в HEX-файл
    with open(output_hex_path, 'w') as f:
        for byte in epd_buffer:
            f.write(f"{byte:02X}\n")
    
    print(f"Image converted to {output_hex_path} successfully!")

# Параметры вашего дисплея (измените под свои нужды)
EPD_WIDTH = 400
EPD_HEIGHT = 300

# Пример использования
input_image = "test_image.png"  # Путь к исходному изображению
output_hex = "image.hex"       # Выходной файл для Verilog

image_to_hex(input_image, output_hex, EPD_WIDTH, EPD_HEIGHT)