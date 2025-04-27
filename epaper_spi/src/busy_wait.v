module busy_wait #(
    parameter TIMEOUT = 32'd50_000_000
)(
    input wire clk,
    input wire reset_n,
    input wire start,
    input wire epd_busy,
    output reg busy,
    output reg done,
    output reg timeout
);

reg [31:0] counter;

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        busy <= 0;
        done <= 0;
        timeout <= 0;
        counter <= 0;
    end else begin
        if (start && !busy) begin
            // Начинаем ожидание
            busy <= 1;
            done <= 0;
            timeout <= 0;
            counter <= 0;
        end else if (busy) begin
            if (!epd_busy) begin
                // BUSY стал низким - завершаем успешно
                busy <= 0;
                done <= 1;
            end else if (counter >= TIMEOUT) begin
                // Таймаут
                busy <= 0;
                timeout <= 1;
            end else begin
                counter <= counter + 1;
            end
        end else begin
            done <= 0;
            timeout <= 0;
        end
    end
end

endmodule