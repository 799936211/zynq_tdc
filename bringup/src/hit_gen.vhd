----------------------------------------------------------------------------------
-- On-chip asynchronous hit generator (ring oscillator)
--
-- A 3-stage inverter ring oscillates at a frequency set only by LUT/routing
-- delays (typically several hundred MHz on 7-series). It is completely
-- uncorrelated with the TDC clock, so the arrival phase of the divided
-- output edges sweeps uniformly across the TDC clock period - exactly the
-- stimulus required for a code-density (DNL/INL) calibration.
--
-- Hit rates (approximate, f_ro ~ 300-600 MHz):
--   hit0 = cnt(TAP0): rising edges at f_ro / 2^(TAP0+1)  ~ 0.6-1.2 MHz (TAP0=8)
--   hit1 = cnt(TAP1): rising edges at f_ro / 2^(TAP1+1)  ~ 0.15-0.3 MHz (TAP1=10)
-- Both far below the TDC dead time / max rate, and different per channel so
-- the two channels can be calibrated simultaneously.
--
-- NOTE: the combinatorial loop triggers DRC LUTLP-1 at bitstream generation;
-- the accompanying tdc_bringup.xdc downgrades that check to a warning.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity hit_gen is
   generic (
      TAP0 : natural := 8;    -- divider tap for hit0
      TAP1 : natural := 10    -- divider tap for hit1
   );
   port (
      hit0 : out std_logic;
      hit1 : out std_logic
   );
end hit_gen;

architecture rtl of hit_gen is
   signal ro  : std_logic_vector(2 downto 0);
   signal cnt : unsigned(15 downto 0) := (others => '0');

   -- keep the ring from being optimized away
   attribute KEEP       : string;
   attribute DONT_TOUCH : string;
   attribute KEEP       of ro : signal is "TRUE";
   attribute DONT_TOUCH of ro : signal is "TRUE";
begin

   -- 3-inverter ring oscillator (intentional combinatorial loop)
   ro(0) <= not ro(2);
   ro(1) <= not ro(0);
   ro(2) <= not ro(1);

   -- divide down in the ring's own (async) clock domain
   process(ro(0))
   begin
      if rising_edge(ro(0)) then
         cnt <= cnt + 1;
      end if;
   end process;

   hit0 <= cnt(TAP0);
   hit1 <= cnt(TAP1);

end rtl;
