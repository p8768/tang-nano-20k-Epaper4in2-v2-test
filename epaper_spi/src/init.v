
module init(
    input wire [7:0] addr,
    output reg [7:0] command,
    output reg is_data
);

always @(*) begin
    case(addr)
        // Адрес | Команда | Флаг данных (1=data, 0=command)
        8'h00: begin command = 8'h12; is_data = 0; end 
        8'h01: begin command = 8'h21; is_data = 0; end
        8'h02: begin command = 8'h40; is_data = 1; end 
        8'h03: begin command = 8'h00; is_data = 1; end 
        8'h04: begin command = 8'h3C; is_data = 0; end  
        8'h05: begin command = 8'h05; is_data = 1; end  
        8'h06: begin command = 8'h11; is_data = 0; end  
        8'h07: begin command = 8'h03; is_data = 1; end 

        8'h08: begin command = 8'h44; is_data = 0; end  
        8'h09: begin command = 8'h00; is_data = 1; end  
        8'h0A: begin command = 8'h31; is_data = 1; end  
        8'h0B: begin command = 8'h45; is_data = 0; end 
        8'h0C: begin command = 8'h00; is_data = 1; end  
        8'h0D: begin command = 8'h00; is_data = 1; end  
        8'h0E: begin command = 8'h2B; is_data = 1; end  
        8'h0F: begin command = 8'h01; is_data = 1; end 

        8'h10: begin command = 8'h4E; is_data = 0; end  
        8'h11: begin command = 8'h00; is_data = 1; end  
        8'h12: begin command = 8'h4F; is_data = 0; end  
        8'h13: begin command = 8'h00; is_data = 1; end
        8'h14: begin command = 8'h00; is_data = 1; end 

        default: begin command = 8'h00; is_data = 0; end
    endcase
end

endmodule
