module spi #(
    parameter EPD_WIDTH = 400,
    parameter EPD_HEIGHT = 300,
    parameter CLK_FREQ = 12_000_000,
    parameter STARTUP_WAIT = 32'd1000,
    parameter BUSY_TIMEOUT = 32'd50_000_000
)(
    input wire clk,
    input wire reset_ne,
    output wire epd_sclk,
    output wire epd_sdin,
    output wire epd_cs,
    output wire epd_dc,
    output wire epd_res,
    input wire epd_busy
);
    wire reset_n = ~reset_ne;
localparam BUFFER_SIZE = ((EPD_WIDTH/8)*EPD_HEIGHT)*2;

// Добавляем новый параметр для контекста DISPLAY
localparam 
    DISPLAY_AFTER_CLEAR = 0,
    DISPLAY_AFTER_LOAD = 1;

localparam 
    S_IDLE      = 0,
    S_RESET     = 1,
    S_INIT      = 2,
    S_CLEAR     = 3,
    S_LOAD_IMG  = 4,  // Новое состояние для загрузки изображения
    S_DISPLAY   = 5,
    S_SLEEP     = 6,
    S_DONE      = 7;

// Регистры для работы с init модулем
reg [7:0] init_addr = 0;
wire [7:0] init_command;
wire init_is_data;

// Экземпляр модуля init
init init_rom(
    .addr(init_addr),
    .command(init_command),
    .is_data(init_is_data)
);

// Память для изображения
(* ram_style = "block" *) reg [7:0] image_mem [0:BUFFER_SIZE-1];

// Инициализация памяти из hex-файла
initial begin
    $readmemh("image.hex", image_mem);
end

// Регистры управления
reg [31:0] counter = 0;
reg [2:0] state = S_IDLE;
reg [7:0] spi_data;
reg spi_start = 0;
reg spi_busy = 0;
reg [3:0] bit_count;
reg [15:0] data_counter;
reg [31:0] init_step = 0; // 2

reg [5:0] clear_step = 0; // Счетчик шагов очистки
// Добавляем регистр для хранения контекста
reg display_context;
// Регистры выходных сигналов
reg dc = 1;
reg sclk = 0;
reg sdin = 0;
reg reset = 1;
reg cs = 1;

// Сигналы для модуля busy_wait
reg wait_busy_start = 0;
wire wait_busy_done;
wire wait_busy_timeout;

// Присвоение выходных сигналов
assign epd_sclk = sclk;
assign epd_sdin = sdin;
assign epd_dc = dc;
assign epd_res = reset;
assign epd_cs = cs;

// Экземпляр модуля ожидания BUSY
busy_wait #(
    .TIMEOUT(BUSY_TIMEOUT)
) busy_wait_inst (
    .clk(clk),
    .reset_n(reset_n),
    .start(wait_busy_start),
    .epd_busy(epd_busy),
    .busy(),
    .done(wait_busy_done),
    .timeout(wait_busy_timeout)
);
// SPI передатчик
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        // Сброс всех сигналов при активации reset_n (активный низкий уровень)
        sclk <= 0;          // Сбрасываем тактовый сигнал SPI
        sdin <= 0;          // Сбрасываем линию данных
        bit_count <= 0;     // Сбрасываем счетчик битов
        spi_busy <= 0;      // Сбрасываем флаг занятости
    end else begin
        // Если получен сигнал старта и SPI не занят
        if (spi_start && !spi_busy) begin
            spi_busy <= 1;          // Устанавливаем флаг занятости
            bit_count <= 7;         // Начинаем с самого старшего бита (MSB)
            sdin <= spi_data[7];    // Загружаем старший бит данных в линию sdin
            sclk <= 0;              // Устанавливаем тактовый сигнал в низкий уровень
        end 
        // Если SPI занят (передача активна)
        else if (spi_busy) begin
            if (sclk) begin
                // Если тактовый сигнал высокий, переводим его в низкий уровень
                sclk <= 0;
                
                // Если еще есть биты для передачи
                if (bit_count > 0) begin
                    sdin <= spi_data[bit_count-1];  // Загружаем следующий бит данных
                    bit_count <= bit_count - 1;    // Уменьшаем счетчик битов
                end else begin
                    spi_busy <= 0;  // Если все биты переданы, сбрасываем флаг занятости
                end
            end else begin
                // Если тактовый сигнал низкий, переводим его в высокий уровень
                sclk <= 1;
            end
        end
    end
end

// Главный конечный автомат
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= S_IDLE;
        reset <= 1;
        dc <= 0;
        cs <= 1;
        counter <= 0;
        init_addr <= 0;
        spi_start <= 0;
        data_counter <= 0;
        init_step <= 0;
        wait_busy_start <= 0;
        clear_step <= 0;
    end else begin
        // Сбрасываем сигнал start для модуля busy_wait
        wait_busy_start <= 0;
        spi_start <= 0;       
        case (state)
            S_IDLE: begin
                state <= S_RESET;
                counter <= 0;
            end
            
            S_RESET: begin
                counter <= counter + 1;
                // Последовательность сигналов сброса
                if (counter < STARTUP_WAIT) begin
                    reset <= 1;
                end else if (counter < STARTUP_WAIT * 2) begin
                    reset <= 0;
                end else if (counter < STARTUP_WAIT * 3) begin
                    reset <= 1;
                end else begin
                    state <= S_INIT;
                    counter <= 0;
                    init_addr <= 0;
                    init_step <= 0;
                end
            end
            
            S_INIT: begin
                if (init_addr <= 8'h14) begin
                    case (init_step)
                        0: begin
                            // Устанавливаем сигналы DC и CS
                            dc <= init_is_data;
                            cs <= 0;
                            init_step <= init_step + 1;
                        end
                        1: begin
                            // Загружаем данные и запускаем передачу
                            spi_data <= init_command;
                            spi_start <= 1;
                            init_step <= init_step + 1;
                        end
                        2: begin
                            // Ждем начала передачи
                            if (spi_busy) begin
                                spi_start <= 0;
                                init_step <= init_step + 1;
                            end
                        end
                        3: begin
                            // Ждем завершения передачи
                            if (!spi_busy) begin
                                cs <= 1; // Деактивируем CS после передачи
                                
                                // Если это первая команда (0x12), запускаем ожидание BUSY
                                if (init_addr == 8'h00) begin
                                    wait_busy_start <= 1;
                                    init_step <= init_step + 1;
                                end else begin
                                    init_addr <= init_addr + 1;
                                    init_step <= 0;
                                end
                            end
                        end
                        4: begin
                            // Ожидаем завершения ожидания BUSY
                            if (wait_busy_done || wait_busy_timeout) begin
                                init_addr <= init_addr + 1;
                                init_step <= 0;
                            end
                        end
                    endcase
                end else begin
                    // Ожидание завершения инициализации
                    if (!epd_busy || counter >= BUSY_TIMEOUT) begin
                        counter <= 0;
                        spi_start <= 0; 
                        state <= S_CLEAR;
                    end else begin
                        counter <= counter + 1;
                    end
                end
            end
            
S_CLEAR: begin
    if (!spi_busy) begin
        case (clear_step)
            // 1. Отправка команды 0x24 (основной буфер)
            0: begin
                dc <= 0;
                cs <= 0;
                spi_data <= 8'h24;
                spi_start <= 1;
                clear_step <= clear_step + 1;
            end

            // 2. Подготовка к отправке данных в основной буфер
            1: begin
                spi_start <= 0;
                dc <= 1;
                data_counter <= 0;
                clear_step <= clear_step + 1;
            end

            // 3. Заполнение основного буфера (0xFF)
            2: begin
                if (data_counter < BUFFER_SIZE) begin
                    spi_data <= 8'hFF;
                    spi_start <= 1;
                    data_counter <= data_counter + 1;
                end else begin
                    spi_start <= 0;
                    clear_step <= clear_step + 1;
                end
            end

            // 4. Завершение записи в основной буфер
            3: begin
                cs <= 1;
                clear_step <= clear_step + 1;
            end

            // 5. Подготовка к отправке команды 0x26
            4: begin
                dc <= 0;
                cs <= 0;
                spi_data <= 8'h26;
                spi_start <= 1;
                clear_step <= clear_step + 1;
            end

            // 6. Подготовка к отправке данных в дополнительный буфер
            5: begin
                spi_start <= 0;
            //    dc <= 1;
                data_counter <= 0;
                clear_step <= clear_step + 1;
            end

            // 7. Заполнение дополнительного буфера (0xFF)
            6: begin
                if (data_counter < BUFFER_SIZE) begin
                    dc <= 1;
                    spi_data <= 8'hFF;
                    spi_start <= 1;
                    data_counter <= data_counter + 1;
                end else begin
                    spi_start <= 0;
                    clear_step <= clear_step + 1;
                end
            end

            // 8. Завершение очистки
            7: begin
                cs <= 1;
                clear_step <= 0;
                spi_start <= 0;
                counter <= 0;
                display_context <= DISPLAY_AFTER_CLEAR;
                state <= S_DISPLAY;
            end

        endcase

    end else begin
        spi_start <= 0;
        counter <= 0;
    end
end


S_LOAD_IMG: begin
    if (!spi_busy) begin
        case (counter)
            // Команда 0x24 (запись в основной буфер)
            0: begin
                dc <= 0;
                cs <= 0;
                spi_data <= 8'h24;
                spi_start <= 1;
                counter <= counter + 1;
                data_counter <= 0;
            end
            // Ожидание завершения передачи команды
            1: begin
                spi_start <= 0;
                if (!spi_busy) begin
                    counter <= counter + 1;
                end
            end
            // Отправка данных изображения (основной буфер)
            2: begin
                dc <= 1;
                if (data_counter < BUFFER_SIZE) begin
                    spi_data <= image_mem[data_counter];
                    spi_start <= 1;
                    data_counter <= data_counter + 1;
                end else begin
                    counter <= counter + 1;
                end
            end
            // Ожидание завершения передачи последнего байта
            3: begin
                spi_start <= 0;
                if (!spi_busy) begin
                    counter <= counter + 1;
                end
            end
            // Команда 0x26 (запись в дополнительный буфер)
            4: begin
                dc <= 0;
                spi_data <= 8'h26;
                spi_start <= 1;
                counter <= counter + 1;
                data_counter <= 0;
            end
            // Ожидание завершения передачи команды
            5: begin
                spi_start <= 0;
                if (!spi_busy) begin
                    counter <= counter + 1;
                end
            end
            // Отправка данных изображения (дополнительный буфер)
            6: begin
                dc <= 1;
                if (data_counter < BUFFER_SIZE) begin
                    spi_data <= image_mem[data_counter];
                    spi_start <= 1;
                    data_counter <= data_counter + 1;
                end else begin
                    counter <= counter + 1;
                end
            end
            // Завершение и переход к обновлению дисплея
            7: begin
                spi_start <= 0;
                if (!spi_busy) begin
                    cs <= 1;
                    counter <= 0;
                    display_context <= DISPLAY_AFTER_LOAD;
                    state <= S_DISPLAY;
                end
            end
        endcase
    end else begin
        spi_start <= 0;
    end
end


// Новое состояние для обновления дисплея
S_DISPLAY: begin
    if (!spi_busy) begin
        case (counter)
            // Команда 0x22 (Display Update Control)
            0: begin
                dc <= 0;        // Команда
                cs <= 0;        // Активируем чип
                spi_data <= 8'h22;
                spi_start <= 1;
                counter <= counter + 1;
            end
            // Ожидание завершения передачи команды
            1: begin
                spi_start <= 0;
                if (!spi_busy) begin
                    counter <= counter + 1;
                end
            end
            // Данные 0xF7
            2: begin
                dc <= 1;        // Данные
                spi_data <= 8'hF7;
                spi_start <= 1;
                counter <= counter + 1;
            end
            // Ожидание завершения передачи данных
            3: begin
                spi_start <= 0;
                if (!spi_busy) begin
                    counter <= counter + 1;
                end
            end
            // Команда 0x20 (Master Activation)
            4: begin
                dc <= 0;        // Команда
                spi_data <= 8'h20;
                spi_start <= 1;
                counter <= counter + 1;
            end
            // Ожидание завершения передачи команды
            5: begin
                spi_start <= 0;
                if (!spi_busy) begin
                    counter <= counter + 1;
                end
            end
            // Завершение и ожидание BUSY
            6: begin
                cs <= 1;        // Деактивируем чип
                wait_busy_start <= 1;
               if (wait_busy_done || wait_busy_timeout) begin
                    // В зависимости от контекста выбираем следующее состояние
                    if (display_context == DISPLAY_AFTER_CLEAR) begin
                        state <= S_LOAD_IMG; // После очистки загружаем изображение
                    end else begin
                        state <= S_SLEEP;   // После загрузки изображения переходим в сон
                    end
                    counter <= 0;
                end
            end
        endcase
    end else begin
        spi_start <= 0;
    end
end
            
            S_SLEEP: begin
                if (!epd_busy) begin
                    case (counter)
                        0: begin dc <= 0; cs <= 0; spi_data <= 8'h10; spi_start <= 1; end
                        1: begin dc <= 1; spi_data <= 8'h01; spi_start <= 1; end
                        default: begin
                            cs <= 1;
                            state <= S_DONE;
                        end
                    endcase
                    counter <= counter + 1;
                end else begin

                    spi_start <= 0;
                end
            end
            
            S_DONE: begin
                // Тест завершен
    // 1. Остановка всех активных процессов
    spi_start <= 0;          // Прекращаем любые SPI передачи
    wait_busy_start <= 0;    // Отключаем ожидание BUSY
    
    // 2. Безопасное состояние выходных сигналов дисплея
    dc <= 0;                 // Переводим DC в режим команд (на случай последующей инициализации)
    cs <= 1;                 // Деактивируем выбор чипа (высокий уровень)
 //   sclk <= 0;               // Фиксируем тактовый сигнал в 0
//    sdin <= 0;               // Фиксируем линию данных в 0
    reset <= 1;              // Держим дисплей в состоянии сброса (активный уровень зависит от дисплея)
    
    // 3. Сброс всех временных регистров и счетчиков
    counter <= 0;            // Сбрасываем основной счетчик
    data_counter <= 0;       // Сбрасываем счетчик данных
    init_step <= 0;          // Сбрасываем шаг инициализации
    clear_step <= 0;         // Сбрасываем шаг очистки
    init_addr <= 0;          // Сбрасываем адрес инициализации
    
    // 4. Дополнительно можно добавить:
    // - Флаг завершения для внешнего управления
    // - Возможность выхода из S_DONE по внешнему сигналу
    
    // Состояние остается в S_DONE до сброса системы
            end
        endcase
    end
end

endmodule