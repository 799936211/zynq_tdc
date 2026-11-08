----------------------------------------------------------------------------------
-- TDC Board Bring-up Top (ALINX AX7010, pure PL, no PS required)
--
-- Purpose:
--   Stage-1 board verification for the zynq_tdc project before xsa/Vitis work.
--   Instantiates the unmodified TDCchannel VHDL from AXITDC/src directly,
--   clocked at 300 MHz from the on-board 50 MHz PL oscillator (U18).
--
-- Features:
--   * Heartbeat LED  -> verifies clk_wiz locked & 300 MHz domain alive
--   * Hit-activity LED -> toggles on every ch0 timestamp written
--   * VIO: hit source select (KEY / ring oscillator), soft clear, run
--   * ILA: timestamp capture with storage qualification (one sample per hit)
--   * hit_gen: on-chip ring-oscillator stimulus, uncorrelated to TDC clock,
--     for code-density (DNL/INL) calibration without any external hardware
--
-- Data format (from control.vhd, 64-bit BRAM word):
--   data(31 downto 0)  = timestamp = coarse(24b) & fine(8b), fine = bin index
--   data(52 downto 32) = trigger index (unused here, tied to 0)
--   data(63 downto 53) = zero padding
--
-- F117, 2026-11-08
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tdc_bringup_top is
   generic (
      NTaps : integer := 192   -- must match the main project; multiple of 12
   );
   port (
      clk50 : in  std_logic;                     -- PL 50 MHz oscillator, U18
      key0  : in  std_logic;                     -- KEY1, N15 -> hit0 source
      key1  : in  std_logic;                     -- KEY2, N16 -> hit1 source
      led   : out std_logic_vector(1 downto 0)   -- M14 / M15
   );
end tdc_bringup_top;

architecture rtl of tdc_bringup_top is

   constant ADDR_WIDTH : integer := 11;          -- fixed by TDCchannel/AXITDC
   constant ZERO_ADDR  : std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');

   -- Clock wizard: 50 MHz -> 300 MHz (matches the main project's derated clock)
   component clk_wiz_0 is
      port (
         clk_in1  : in  std_logic;
         clk_out1 : out std_logic;
         locked   : out std_logic
      );
   end component;

   -- VIO: in0/in1 = hit counters; out0 = hit_sel, out1 = soft clr, out2 = run
   component vio_0 is
      port (
         clk        : in  std_logic;
         probe_in0  : in  std_logic_vector(31 downto 0);
         probe_in1  : in  std_logic_vector(31 downto 0);
         probe_out0 : out std_logic_vector(0 downto 0);
         probe_out1 : out std_logic_vector(0 downto 0);
         probe_out2 : out std_logic_vector(0 downto 0)
      );
   end component;

   -- ILA: one sample per timestamp write (storage qualification on we)
   component ila_0 is
      port (
         clk    : in std_logic;
         probe0 : in std_logic_vector(0 downto 0);    -- we0[0]  (trigger + qualifier)
         probe1 : in std_logic_vector(31 downto 0);   -- ts0 = coarse & fine
         probe2 : in std_logic_vector(0 downto 0);    -- we1[0]  (trigger + qualifier)
         probe3 : in std_logic_vector(31 downto 0);   -- ts1
         probe4 : in std_logic_vector(3 downto 0);    -- status
         probe5 : in std_logic_vector(10 downto 0)    -- addr0 (write index)
      );
   end component;

   signal clk300 : std_logic;
   signal locked : std_logic;

   signal sel_v, clr_v, run_v : std_logic_vector(0 downto 0);
   signal hit_sel, clr, run   : std_logic;

   signal ro_hit0, ro_hit1 : std_logic;
   signal hit0, hit1       : std_logic;

   signal addr0, addr1 : std_logic_vector(ADDR_WIDTH-1 downto 0);
   signal data0, data1 : std_logic_vector(63 downto 0);
   signal we0,   we1   : std_logic_vector(7 downto 0);
   signal rdy0, rdy1, full0, full1 : std_logic;

   signal hitcnt0, hitcnt1 : unsigned(31 downto 0) := (others => '0');
   signal hb     : unsigned(27 downto 0) := (others => '0');
   signal act0   : std_logic := '0';
   signal status : std_logic_vector(3 downto 0);

begin

   ----------------------------------------------------------------------------
   -- Clocking: 50 MHz board oscillator -> MMCM -> 300 MHz TDC clock
   ----------------------------------------------------------------------------
   clkgen : clk_wiz_0
      port map (
         clk_in1  => clk50,
         clk_out1 => clk300,
         locked   => locked
      );

   -- Hold the TDC FSM in CLEAR while the MMCM is unlocked
   clr <= (not locked) or clr_v(0);
   run <= run_v(0);

   ----------------------------------------------------------------------------
   -- On-chip asynchronous hit stimulus (ring oscillator), for code-density
   ----------------------------------------------------------------------------
   stim : entity work.hit_gen(rtl)
      port map (
         hit0 => ro_hit0,
         hit1 => ro_hit1
      );

   -- hit_sel = 0: external keys (smoke test)
   -- hit_sel = 1: ring oscillator (code-density calibration)
   hit0 <= key0 when hit_sel = '0' else ro_hit0;
   hit1 <= key1 when hit_sel = '0' else ro_hit1;

   ----------------------------------------------------------------------------
   -- Two unmodified TDC channels, BRAM outputs observed instead of stored
   ----------------------------------------------------------------------------
   ch0 : entity work.TDCchannel(rtl)
      generic map (
         NTaps      => NTaps,
         ADDR_WIDTH => ADDR_WIDTH
      )
      port map (
         clk         => clk300,
         hit         => hit0,
         addr        => addr0,
         data        => data0,
         we          => we0,
         run         => run,
         clr         => clr,
         rdy         => rdy0,
         full        => full0,
         trigger_in  => ZERO_ADDR,
         trigger_out => open
      );

   ch1 : entity work.TDCchannel(rtl)
      generic map (
         NTaps      => NTaps,
         ADDR_WIDTH => ADDR_WIDTH
      )
      port map (
         clk         => clk300,
         hit         => hit1,
         addr        => addr1,
         data        => data1,
         we          => we1,
         run         => run,
         clr         => clr,
         rdy         => rdy1,
         full        => full1,
         trigger_in  => ZERO_ADDR,
         trigger_out => open
      );

   ----------------------------------------------------------------------------
   -- Indicators & counters
   ----------------------------------------------------------------------------
   process(clk300)
   begin
      if rising_edge(clk300) then
         hb <= hb + 1;
         if we0 = x"FF" then
            hitcnt0 <= hitcnt0 + 1;
            act0    <= not act0;        -- visual hit indicator
         end if;
         if we1 = x"FF" then
            hitcnt1 <= hitcnt1 + 1;
         end if;
      end if;
   end process;

   led(0) <= hb(27);     -- ~1.1 Hz heartbeat @300 MHz: clock domain alive
   led(1) <= act0;       -- toggles once per ch0 timestamp

   status <= full1 & rdy1 & full0 & rdy0;

   ----------------------------------------------------------------------------
   -- Debug
   ----------------------------------------------------------------------------
   dbg_vio : vio_0
      port map (
         clk        => clk300,
         probe_in0  => std_logic_vector(hitcnt0),
         probe_in1  => std_logic_vector(hitcnt1),
         probe_out0 => sel_v,
         probe_out1 => clr_v,
         probe_out2 => run_v
      );

   dbg_ila : ila_0
      port map (
         clk    => clk300,
         probe0 => we0(0 downto 0),
         probe1 => data0(31 downto 0),
         probe2 => we1(0 downto 0),
         probe3 => data1(31 downto 0),
         probe4 => status,
         probe5 => addr0
      );

end rtl;
