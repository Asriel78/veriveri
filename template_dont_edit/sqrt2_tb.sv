`ifdef BEHAVIOUR
`include "sqrt2_b.sv"
`elsif STRUCTURAL
`include "sqrt2_s.sv"
`else
`error "!mode"
`endif

// put your code here
module sqrt2_tb; 
	reg CLK;
	integer fd, failed;
	
	initial begin
		CLK = 0;
		failed = 0;
		
		fd = $fopen("sqrt2_log.csv", "w");
		// ...		
		#2;
        $fclose(fd);
        
		if (failed) begin
			$fatal(2, "!all passed"); 
		end

		$finish(2);
	end

	always #1 CLK = ~CLK;

	always @(CLK) begin
        $fstrobe(fd, "%d\t%b", $time, CLK);
    end    

endmodule

