module iterate (
    input  wire        clk,
    input  wire        enable,
    input  wire        n_valid,

    input  wire        is_nan_in,
    input  wire        is_pinf_in,
    input  wire        is_ninf_in,
    input  wire        is_num,

    input  wire        sign_in,
    input  wire [10:0] mant_in,
    input  wire signed [6:0] exp_in,

    output wire        it_valid,
    output wire        result,

    output wire        sign_out,
    output wire signed [6:0] exp_out,
    output wire [10:0] mant_out,
    
    output wire        is_nan_out,
    output wire        is_pinf_out,
    output wire        is_ninf_out
);

    wire active;
    wire [3:0] iter_left;
    wire [33:0] radicand;
    wire [22:0] remainder;
    wire [11:0] root;
    wire is_special;
    wire stored_is_nan, stored_is_pinf, stored_is_ninf;

    wire exp_is_minus15, mant_is_zero, is_zero;
    comparator_eq_n #(.WIDTH(7)) exp_cmp(
        .a(exp_in), 
        .b(7'b1110001), 
        .eq(exp_is_minus15)
    );
    is_zero_n #(.WIDTH(11)) mant_check(.in(mant_in), .is_zero(mant_is_zero));
    and(is_zero, exp_is_minus15, mant_is_zero);

    wire not_is_num, is_special_input;
    not(not_is_num, is_num);
    or(is_special_input, not_is_num, is_nan_in, is_pinf_in, is_ninf_in);
    
    wire active_n, start_trigger;
    not(active_n, active);
    and(start_trigger, n_valid, active_n);

    wire iter_eq_1, iter_not_1;
    comparator_eq_n #(.WIDTH(4)) iter_check(.a(iter_left), .b(4'd1), .eq(iter_eq_1));
    not(iter_not_1, iter_eq_1);
    
    wire not_zero, not_special, start_compute;
    not(not_zero, is_zero);
    not(not_special, is_special_input);
    and(start_compute, start_trigger, not_zero, not_special);
    
    wire active_stay, active_next;
    and(active_stay, active, iter_not_1);
    or(active_next, start_compute, active_stay);

    wire signed [6:0] exp_halved;
    wire [11:0] mant_prepared;
    sqrt_input_prepare prep(
        .exp_in(exp_in),
        .mant_in(mant_in),
        .exp_halved(exp_halved),
        .mant_prepared(mant_prepared)
    );
    
    wire [11:0] root_next;
    wire [22:0] remainder_next;
    wire [33:0] radicand_next;
    sqrt_iteration_core iteration(
        .root(root),
        .remainder(remainder),
        .radicand(radicand),
        .root_next(root_next),
        .remainder_next(remainder_next),
        .radicand_next(radicand_next)
    );
    
    wire [10:0] mant_computing;
    sqrt_output_formatter formatter(
        .root(root_next),
        .iter_left(iter_left),
        .mant_out(mant_computing)
    );

    wire [3:0] iter_decremented;
    decrement_n #(.WIDTH(4)) iter_dec(.in(iter_left), .out(iter_decremented));
    
    wire [3:0] iter_start_val, iter_next_internal;
    mux2_n #(.WIDTH(4)) iter_start_mux(
        .a(iter_left), 
        .b(4'd11), 
        .sel(start_compute), 
        .out(iter_start_val)
    );
    mux2_n #(.WIDTH(4)) iter_active_mux(
        .a(iter_start_val), 
        .b(iter_decremented), 
        .sel(active), 
        .out(iter_next_internal)
    );
    
    wire [33:0] radicand_start_val, radicand_next_internal;
    mux2_n #(.WIDTH(34)) rad_start_mux(
        .a(radicand), 
        .b({mant_prepared, 22'd0}), 
        .sel(start_compute), 
        .out(radicand_start_val)
    );
    mux2_n #(.WIDTH(34)) rad_active_mux(
        .a(radicand_start_val), 
        .b(radicand_next), 
        .sel(active), 
        .out(radicand_next_internal)
    );
    
    wire [22:0] remainder_start_val, remainder_next_internal;
    mux2_n #(.WIDTH(23)) rem_start_mux(
        .a(remainder), 
        .b(23'd0), 
        .sel(start_compute), 
        .out(remainder_start_val)
    );
    mux2_n #(.WIDTH(23)) rem_active_mux(
        .a(remainder_start_val), 
        .b(remainder_next), 
        .sel(active), 
        .out(remainder_next_internal)
    );
    
    wire [11:0] root_start_val, root_next_internal;
    mux2_n #(.WIDTH(12)) root_start_mux(
        .a(root), 
        .b(12'd0), 
        .sel(start_compute), 
        .out(root_start_val)
    );
    mux2_n #(.WIDTH(12)) root_active_mux(
        .a(root_start_val), 
        .b(root_next), 
        .sel(active), 
        .out(root_next_internal)
    );
    
    wire spec_detected;
    or(spec_detected, is_zero, is_special_input);
    
    wire spec_keep, spec_held, is_special_next_internal;
    and(spec_keep, start_trigger, spec_detected);
    and(spec_held, is_special, active_n);
    or(is_special_next_internal, spec_keep, spec_held);
    
    wire store_flags, is_nan_or_ninf;
    and(store_flags, start_trigger, is_special_input);
    or(is_nan_or_ninf, is_nan_in, is_ninf_in);
    
    wire store_nan, store_pinf;
    and(store_nan, store_flags, is_nan_or_ninf);
    and(store_pinf, store_flags, is_pinf_in);
    
    wire keep_nan, keep_pinf, keep_ninf;
    and(keep_nan, stored_is_nan, active_n);
    and(keep_pinf, stored_is_pinf, active_n);
    and(keep_ninf, stored_is_ninf, active_n);
    
    wire snan_next_internal, spinf_next_internal, sninf_next_internal;
    or(snan_next_internal, store_nan, keep_nan);
    or(spinf_next_internal, store_pinf, keep_pinf);
    or(sninf_next_internal, keep_ninf);

    wire it_valid_next_internal;
    or(it_valid_next_internal, start_trigger, active);
    
    wire result_start, result_active, result_from_special, result_next_internal;
    and(result_start, start_trigger, spec_detected);
    and(result_active, active, iter_eq_1);
    and(result_from_special, is_special, active_n);
    wire result_or1;
    or(result_or1, result_start, result_active);
    or(result_next_internal, result_or1, result_from_special);
    
    wire sign_for_zero, sign_for_special, sign_for_compute;
    and(sign_for_zero, start_trigger, is_zero);
    and(sign_for_special, start_trigger, is_special_input);
    and(sign_for_compute, start_trigger, not_zero, not_special);
    
    wire sign_special_value;
    mux2 sign_spec_mux(.a(sign_in), .b(1'b1), .sel(is_ninf_in), .out(sign_special_value));
    
    wire sign_choice1, sign_choice2, sign_next_internal;
    mux2 sign_m1(.a(sign_out), .b(sign_in), .sel(sign_for_zero), .out(sign_choice1));
    mux2 sign_m2(.a(sign_choice1), .b(sign_special_value), .sel(sign_for_special), .out(sign_choice2));
    mux2 sign_m3(.a(sign_choice2), .b(1'b0), .sel(sign_for_compute), .out(sign_next_internal));
    
    wire signed [6:0] exp_for_zero = 7'b1110001;
    wire signed [6:0] exp_for_special = 7'sd16;
    wire signed [6:0] exp_choice1, exp_choice2, exp_next_internal;
    mux2_n #(.WIDTH(7)) exp_m1(.a(exp_out), .b(exp_for_zero), .sel(sign_for_zero), .out(exp_choice1));
    mux2_n #(.WIDTH(7)) exp_m2(.a(exp_choice1), .b(exp_for_special), .sel(sign_for_special), .out(exp_choice2));
    mux2_n #(.WIDTH(7)) exp_m3(.a(exp_choice2), .b(exp_halved), .sel(sign_for_compute), .out(exp_next_internal));
    
    wire [10:0] mant_for_zero = 11'd0;
    wire [10:0] mant_for_ninf = 11'b11000000000;
    wire [10:0] mant_for_special;
    mux2_n #(.WIDTH(11)) mant_spec_mux(.a(mant_in), .b(mant_for_ninf), .sel(is_ninf_in), .out(mant_for_special));
    
    wire [10:0] mant_choice1, mant_choice2, mant_choice3, mant_next_internal;
    mux2_n #(.WIDTH(11)) mant_m1(.a(mant_out), .b(mant_for_zero), .sel(sign_for_zero), .out(mant_choice1));
    mux2_n #(.WIDTH(11)) mant_m2(.a(mant_choice1), .b(mant_for_special), .sel(sign_for_special), .out(mant_choice2));
    mux2_n #(.WIDTH(11)) mant_m3(.a(mant_choice2), .b(mant_out), .sel(sign_for_compute), .out(mant_choice3));
    mux2_n #(.WIDTH(11)) mant_m4(.a(mant_choice3), .b(mant_computing), .sel(active), .out(mant_next_internal));

    wire restore_flags;
    and(restore_flags, is_special, active_n);
    
    wire nan_spec, pinf_spec, nan_restore, pinf_restore, ninf_restore;
    and(nan_spec, start_trigger, is_special_input, is_nan_or_ninf);
    and(pinf_spec, start_trigger, is_special_input, is_pinf_in);
    and(nan_restore, restore_flags, stored_is_nan);
    and(pinf_restore, restore_flags, stored_is_pinf);
    and(ninf_restore, restore_flags, stored_is_ninf);
    
    wire nan_next_internal, pinf_next_internal, ninf_next_internal;
    or(nan_next_internal, nan_spec, nan_restore);
    or(pinf_next_internal, pinf_spec, pinf_restore);
    or(ninf_next_internal, ninf_restore);

    wire active_d, is_special_d;
    wire [3:0] iter_d;
    wire [33:0] radicand_d;
    wire [22:0] remainder_d;
    wire [11:0] root_d;
    wire snan_d, spinf_d, sninf_d;
    wire it_valid_d, result_d, sign_d;
    wire signed [6:0] exp_d;
    wire [10:0] mant_d;
    wire nan_d, pinf_d, ninf_d;

    wire active_next_gated, is_special_next_gated;
    wire [3:0] iter_next_gated;
    wire [33:0] radicand_next_gated;
    wire [22:0] remainder_next_gated;
    wire [11:0] root_next_gated;
    wire snan_next_gated, spinf_next_gated, sninf_next_gated;
    wire it_valid_next_gated, result_next_gated, sign_next_gated;
    wire signed [6:0] exp_next_gated;
    wire [10:0] mant_next_gated;
    wire nan_next_gated, pinf_next_gated, ninf_next_gated;

    mux2 active_gate(.a(1'b0), .b(active_next), .sel(enable), .out(active_next_gated));
    mux2 special_gate(.a(1'b0), .b(is_special_next_internal), .sel(enable), .out(is_special_next_gated));
    mux2_n #(.WIDTH(4)) iter_gate(.a(4'd0), .b(iter_next_internal), .sel(enable), .out(iter_next_gated));
    mux2_n #(.WIDTH(34)) rad_gate(.a(34'd0), .b(radicand_next_internal), .sel(enable), .out(radicand_next_gated));
    mux2_n #(.WIDTH(23)) rem_gate(.a(23'd0), .b(remainder_next_internal), .sel(enable), .out(remainder_next_gated));
    mux2_n #(.WIDTH(12)) root_gate(.a(12'd0), .b(root_next_internal), .sel(enable), .out(root_next_gated));
    
    mux2 snan_gate(.a(1'b0), .b(snan_next_internal), .sel(enable), .out(snan_next_gated));
    mux2 spinf_gate(.a(1'b0), .b(spinf_next_internal), .sel(enable), .out(spinf_next_gated));
    mux2 sninf_gate(.a(1'b0), .b(sninf_next_internal), .sel(enable), .out(sninf_next_gated));
    
    mux2 valid_gate(.a(1'b0), .b(it_valid_next_internal), .sel(enable), .out(it_valid_next_gated));
    mux2 result_gate(.a(1'b0), .b(result_next_internal), .sel(enable), .out(result_next_gated));
    mux2 sign_gate(.a(1'b0), .b(sign_next_internal), .sel(enable), .out(sign_next_gated));
    mux2_n #(.WIDTH(7)) exp_gate(.a(7'd0), .b(exp_next_internal), .sel(enable), .out(exp_next_gated));
    mux2_n #(.WIDTH(11)) mant_gate(.a(11'd0), .b(mant_next_internal), .sel(enable), .out(mant_next_gated));
    
    mux2 nan_gate(.a(1'b0), .b(nan_next_internal), .sel(enable), .out(nan_next_gated));
    mux2 pinf_gate(.a(1'b0), .b(pinf_next_internal), .sel(enable), .out(pinf_next_gated));
    mux2 ninf_gate(.a(1'b0), .b(ninf_next_internal), .sel(enable), .out(ninf_next_gated));

    dff active_ff(.clk(clk), .d(active_next_gated), .q(active));
    dff special_ff(.clk(clk), .d(is_special_next_gated), .q(is_special));
    register_n #(.WIDTH(4)) iter_reg(.clk(clk), .rst(1'b0), .d(iter_next_gated), .q(iter_left));
    register_n #(.WIDTH(34)) rad_reg(.clk(clk), .rst(1'b0), .d(radicand_next_gated), .q(radicand));
    register_n #(.WIDTH(23)) rem_reg(.clk(clk), .rst(1'b0), .d(remainder_next_gated), .q(remainder));
    register_n #(.WIDTH(12)) root_reg(.clk(clk), .rst(1'b0), .d(root_next_gated), .q(root));
    
    dff snan_ff(.clk(clk), .d(snan_next_gated), .q(stored_is_nan));
    dff spinf_ff(.clk(clk), .d(spinf_next_gated), .q(stored_is_pinf));
    dff sninf_ff(.clk(clk), .d(sninf_next_gated), .q(stored_is_ninf));
    
    dff valid_ff(.clk(clk), .d(it_valid_next_gated), .q(it_valid));
    dff result_ff(.clk(clk), .d(result_next_gated), .q(result));
    dff sign_ff(.clk(clk), .d(sign_next_gated), .q(sign_out));
    register_n #(.WIDTH(7)) exp_reg(.clk(clk), .rst(1'b0), .d(exp_next_gated), .q(exp_out));
    register_n #(.WIDTH(11)) mant_reg(.clk(clk), .rst(1'b0), .d(mant_next_gated), .q(mant_out));
    
    dff nan_ff(.clk(clk), .d(nan_next_gated), .q(is_nan_out));
    dff pinf_ff(.clk(clk), .d(pinf_next_gated), .q(is_pinf_out));
    dff ninf_ff(.clk(clk), .d(ninf_next_gated), .q(is_ninf_out));

endmodule