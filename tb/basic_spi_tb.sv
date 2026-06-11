module basic_spi_tb;

  bit tikka;
  always #10ns tikka = ~tikka;

  localparam real freq = 80e6;

  localparam realtime tSCK = 1s / freq;

  /* verilog_format: off */

    `ifdef SPEEDSIM
        // WRR Cycle Time
        specparam        tdevice_WRR               = 750e6 * 1ps;    //tW = 750us
        
        // Page Program Operation
        specparam        tdevice_PP_256            = 90e6 * 1ps;    //tPP = 90us
        
        // Page Program Operation
        specparam        tdevice_PP_512            = 95e6 * 1ps;    //tPP = 95us
        
        // Sector Erase Operation
        specparam        tdevice_SE4               = 7250e6 * 1ps;    //tSE = 7250us
        
        // Sector Erase Operation
        specparam        tdevice_SE256             = 29e9 * 1ps;    //tSE = 29ms
        
        // Bulk Erase Operation
        specparam        tdevice_BE                = 360e9 * 1ps;    //tBE = 360ms
        
        // Evaluate Erase Status Time
        specparam        tdevice_EES               = 10e6 * 1ps;    //tEES = 10us
        
        // Suspend Latency
        specparam        tdevice_SUSP              = 4e6 * 1ps;    //tSL = 4us
        
        // Resume to next Suspend Time
        specparam        tdevice_RS                = 10e6 * 1ps;    //tRS = 10 us
        
        // RESET# Low to CS# Low
        specparam        tdevice_RPH               = 35e6 * 1ps;    //tRPH = 35 us
        
        // CS# High before HW Reset (Quad mode and Reset Feature are enabled)
        specparam        tdevice_CS                = 20e3 * 1ps;    //tCS = 20 ns
        
        // VDD (min) to CS# Low
        specparam        tdevice_PU                = 300e6 * 1ps;    //tPU = 300us
        
        // Password Unlock to Password Unlock Time
        specparam        tdevice_PASSACC           = 100e6 * 1ps;    // 100us
        
        // CS# High to Power Down Mode
        specparam        tdevice_DPD               = 3e6 * 1ps;    // 3 us
        
        // CS# High to Standby without Electronic Signature
        specparam        tdevice_RES               = 30e6 * 1ps;    // 30 us
        
    `else
        // WRR Cycle Time
        specparam        tdevice_WRR               = 750e9 * 1ps;    //tW = 750ms
        
        // Page Program Operation
        specparam        tdevice_PP_256            = 900e6 * 1ps;    //tPP = 900us
        
        // Page Program Operation
        specparam        tdevice_PP_512            = 950e6 * 1ps;    //tPP = 950us
        
        // Sector Erase Operation
        specparam        tdevice_SE4               = 725e9 * 1ps;    //tSE = 725ms
        
        // Sector Erase Operation
        specparam        tdevice_SE256             = 2900e9 * 1ps;    //tSE = 2900ms
        
        // Bulk Erase Operation
        specparam        tdevice_BE                = 360e12 * 1ps;    //tBE = 360s
        
        // Evaluate Erase Status Time
        specparam        tdevice_EES               = 100e6 * 1ps;    //tEES = 100us
        
        // Suspend Latency
        specparam        tdevice_SUSP              = 40e6 * 1ps;    //tSL = 40us
        
        // Resume to next Suspend Time
        specparam        tdevice_RS                = 100e6 * 1ps;    //tRS = 100 us
        
        // RESET# Low to CS# Low
        specparam        tdevice_RPH               = 35e6 * 1ps;    //tRPH = 35 us
        
        // CS# High before HW Reset (Quad mode and Reset Feature are enabled)
        specparam        tdevice_CS                = 20e3 * 1ps;    //tCS = 20 ns
        
        // VDD (min) to CS# Low
        specparam        tdevice_PU                = 300e6 * 1ps;    //tPU = 300us
        
        // Password Unlock to Password Unlock Time
        specparam        tdevice_PASSACC           = 100e6 * 1ps;    // 100us
        
        // CS# High to Power Down Mode
        specparam        tdevice_DPD               = 3e6 * 1ps;    // 3 us
        
        // CS# High to Standby without Electronic Signature
        specparam        tdevice_RES               = 30e6 * 1ps;    // 30 us
        
    `endif // SPEEDSIM

  /* verilog_format: on */

  tri1  CSNeg;
  tri1  SCK;
  tri1  SI;
  tri1  SO;
  tri1  WPNeg;
  tri1  RESETNeg;

  logic csn = '1;
  logic sck = '1;
  logic mosi = '1;
  logic miso;

  assign CSNeg = csn;
  assign SCK = sck;
  assign SI = mosi;
  assign miso = SO;

  s25fs256s u_dut (.*);

  task automatic set_cs(input bit value = 0);
    #(tdevice_CS);
    csn <= value;
    #(tdevice_CS);
  endtask

  task automatic send(input bit [7:0] data);
    foreach (data[i]) begin
      sck  <= 0;
      mosi <= data[i];
      #(tSCK / 2);
      sck <= 1;
      #(tSCK / 2);
    end
  endtask

  initial begin

    $dumpfile("basic_spi_tb.vcd");
    $dumpvars(0, basic_spi_tb);

    #(tdevice_PU);


    ////// WRITE_ENABLE //////
    set_cs(0);
    send('h06); // CMD: WRITE ENABLE
    set_cs(1);

    ////// WRITE_FAST_4 //////
    set_cs(0);
    send('h12); // CMD: PP4
    send('h31); // ADDR BYTE3
    send('h51); // ADDR BYTE2
    send('h60); // ADDR BYTE1
    send('h11); // ADDR BYTE0
    send('h12); // DATA BYTE0
    send('h34); // DATA BYTE1
    send('h56); // DATA BYTE2
    send('h78); // DATA BYTE3
    set_cs(1);

    #(tdevice_WRR);

    ////// READ_FAST_4 //////
    set_cs(0);
    send('h0C); // CMD: Read
    send('h31); // ADDR BYTE3
    send('h51); // ADDR BYTE2
    send('h60); // ADDR BYTE1
    send('h11); // ADDR BYTE0
    send('h00); // < DUMMY
    send('h00); // DATA BYTE0
    send('h00); // DATA BYTE1
    send('h00); // DATA BYTE2
    send('h00); // DATA BYTE3
    set_cs(1);

    #1us;
    $finish;
  end

endmodule
