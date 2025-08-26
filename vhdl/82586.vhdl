-- NOTE: All example code includes comments, per your preference.
-- This is a *behavioral bus model* you can use to emulate the 82586
-- external bus timing when it performs a single read/write access.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i82586_bus_model is
  generic (
    -- ===== Timing parameters (tweak to match the datasheet) =====
    -- All counts are in 8 MHz clock cycles (125 ns each).
    G_T1_CYCLES      : natural := 1;  -- Address/status valid, start of cycle
    G_T2_CYCLES      : natural := 1;  -- Control strobe assertion window
    G_T3_MIN_CYCLES  : natural := 1;  -- Data phase min before READY sampling
    G_T4_CYCLES      : natural := 1;  -- Deassertion / bus release

    -- Optional insertion of an idle cycle between transactions
    G_INTERCYCLE_GAP : natural := 0;

    -- ===== Encodings for S1:S0 (set to match the 82586 board spec) =====
    -- You can change these later if your hardware doc uses different codes.
    G_SCODE_MEM_RD   : std_logic_vector(1 downto 0) := "10";
    G_SCODE_MEM_WR   : std_logic_vector(1 downto 0) := "11";
    G_SCODE_IDLE     : std_logic_vector(1 downto 0) := "00";

    -- Data bus width (8 or 16; 82586 boards vary). Keep it generic.
    G_DATA_WIDTH     : positive := 16;
    G_ADDR_WIDTH     : positive := 20
  );
  port (
    -- ===== Clk/Reset =====
    clk_8m    : in  std_logic;   -- 8 MHz reference clock
    rst_n     : in  std_logic;

    -- ===== Transaction request (from your TB or master model) =====
    start     : in  std_logic;   -- Pulse or level '1' to initiate a new access
    rw        : in  std_logic;   -- '1' = READ, '0' = WRITE
    addr_in   : in  std_logic_vector(G_ADDR_WIDTH-1 downto 0);
    wdata_in  : in  std_logic_vector(G_DATA_WIDTH-1 downto 0);

    -- ===== Handshake/status back to testbench/master =====
    busy      : out std_logic;   -- '1' while the bus model is in a cycle
    done      : out std_logic;   -- 1-clk pulse when cycle completes
    rdata_out : out std_logic_vector(G_DATA_WIDTH-1 downto 0);

    -- ===== External bus (to your DUT/system) =====
    -- Address and status lines driven by this model.
    A_bus     : out std_logic_vector(G_ADDR_WIDTH-1 downto 0);
    S1        : out std_logic;
    S0        : out std_logic;

    -- Typical active-low strobes (abstracted; map to the exact pins you need).
    CS_n      : out std_logic;
    RD_n      : out std_logic;
    WR_n      : out std_logic;

    -- Bidirectional data bus (resolved). We drive during writes; release on reads.
    D_bus     : inout std_logic_vector(G_DATA_WIDTH-1 downto 0);

    -- Ready/Wait input from the target (insert wait states in T3 while low).
    READY_n   : in  std_logic
  );
end entity;

architecture behav of i82586_bus_model is

  -- ===== Internal types/state =====
  type state_t is (IDLE, T1, T2, T3, T4, GAP);
  signal state, nxt_state : state_t := IDLE;

  signal tcnt : natural := 0;                     -- phase cycle counter
  signal svec : std_logic_vector(1 downto 0);     -- S1:S0 current code

  -- Latched transaction info so inputs can change after 'start'
  signal rw_q       : std_logic := '0';
  signal addr_q     : std_logic_vector(G_ADDR_WIDTH-1 downto 0) := (others=>'0');
  signal wdata_q    : std_logic_vector(G_DATA_WIDTH-1 downto 0) := (others=>'0');

  -- Data output register for READs
  signal rdata_q    : std_logic_vector(G_DATA_WIDTH-1 downto 0) := (others=>'0');

  -- Internal tri-state control for the data bus
  signal d_drive    : std_logic := '0'; -- '1' when we drive D_bus (WRITE)
  signal d_out      : std_logic_vector(G_DATA_WIDTH-1 downto 0) := (others=>'Z');

  -- One-shot for 'done'
  signal done_q     : std_logic := '0';

begin

  -- ===== Combinational mapping for status lines S1,S0 =====
  S1 <= svec(1);
  S0 <= svec(0);

  -- ===== Data bus resolution: drive only on WR cycles during T2/T3 =====
  D_bus <= d_out when d_drive = '1' else (others => 'Z');

  -- ===== Output registers =====
  rdata_out <= rdata_q;
  done      <= done_q;

  -- ===== Synchronous FSM =====
  process(clk_8m, rst_n)
  begin
    if rst_n = '0' then
      state    <= IDLE;
      tcnt     <= 0;
      svec     <= G_SCODE_IDLE;
      A_bus    <= (others => '0');
      CS_n     <= '1';
      RD_n     <= '1';
      WR_n     <= '1';
      d_drive  <= '0';
      d_out    <= (others => 'Z');
      rdata_q  <= (others => '0');
      done_q   <= '0';
      rw_q     <= '0';
      addr_q   <= (others => '0');
      wdata_q  <= (others => '0');

    elsif rising_edge(clk_8m) then
      -- default deassert 'done' each cycle; we’ll pulse it when finishing
      done_q <= '0';

      case state is

        when IDLE =>
          -- Bus idle: status = IDLE, strobes deasserted, tri-state data
          svec    <= G_SCODE_IDLE;
          CS_n    <= '1';
          RD_n    <= '1';
          WR_n    <= '1';
          d_drive <= '0';
          d_out   <= (others => 'Z');
          tcnt    <= 0;

          -- Sample a new request
          if start = '1' then
            -- Latch request inputs so the TB can change them after start
            rw_q    <= rw;
            addr_q  <= addr_in;
            wdata_q <= wdata_in;

            -- Drive address and status for T1
            A_bus   <= addr_in;
            svec    <= (others => '0'); -- temp; set properly below
            -- Choose correct S-code now (T1 shows the cycle type)
            if rw = '1' then
              svec <= G_SCODE_MEM_RD;
            else
              svec <= G_SCODE_MEM_WR;
            end if;

            state <= T1;
          end if;

        when T1 =>
          -- Address and S-lines are valid in T1. Control strobes still deasserted.
          CS_n <= '0';       -- Assert CS# early if your board requires it in T1
          RD_n <= '1';
          WR_n <= '1';
          d_drive <= '0';    -- Not driving yet (even for WR)

          -- T1 duration
          if tcnt + 1 >= G_T1_CYCLES then
            tcnt <= 0;
            state <= T2;

            -- Prepare control strobes for the next phase (assert in T2)
            if rw_q = '1' then
              -- READ cycle: target will drive D_bus; we remain tri-stated
              RD_n <= '0';
              WR_n <= '1';
              d_drive <= '0';
            else
              -- WRITE cycle: we will drive D_bus with wdata_q
              RD_n <= '1';
              WR_n <= '0';
              d_out   <= wdata_q;
              d_drive <= '1';
            end if;

          else
            tcnt <= tcnt + 1;
          end if;

        when T2 =>
          -- Control strobes asserted (RD#/WR#). Address & S-lines remain valid.
          -- If WRITE, data is already being driven; if READ, target will respond.
          if tcnt + 1 >= G_T2_CYCLES then
            tcnt  <= 0;
            state <= T3;
          else
            tcnt <= tcnt + 1;
          end if;

        when T3 =>
          -- Data phase. We allow wait states if READY# is low.
          -- Minimum T3 time first:
          if tcnt + 1 < G_T3_MIN_CYCLES then
            tcnt <= tcnt + 1;
          else
            -- After minimum, hold until READY# is deasserted (i.e., ready = '1')
            if READY_n = '0' then
              -- Insert wait state(s) by staying in T3
              tcnt <= tcnt;  -- hold counter (optional)
            else
              -- READY received: for READ, capture the data now
              if rw_q = '1' then
                rdata_q <= D_bus;
              end if;

              -- Move to T4 (deassertion)
              tcnt  <= 0;
              state <= T4;
            end if;
          end if;

        when T4 =>
          -- Deassert control strobes; keep address stable if your board needs it.
          RD_n    <= '1';
          WR_n    <= '1';
          d_drive <= '0';     -- release bus after WR
          d_out   <= (others => 'Z');

          if tcnt + 1 >= G_T4_CYCLES then
            -- End of cycle
            tcnt   <= 0;
            done_q <= '1';    -- one-shot pulse to signal completion

            -- Optionally insert a gap (idle clocks) before next transaction
            if G_INTERCYCLE_GAP > 0 then
              state <= GAP;
            else
              -- Return to fully idle defaults
              CS_n  <= '1';
              svec  <= G_SCODE_IDLE;
              state <= IDLE;
            end if;

          else
            tcnt <= tcnt + 1;
          end if;

        when GAP =>
          -- Idle gap between cycles (all deasserted)
          CS_n  <= '1';
          RD_n  <= '1';
          WR_n  <= '1';
          svec  <= G_SCODE_IDLE;
          d_drive <= '0';
          d_out <= (others => 'Z');

          if tcnt + 1 >= G_INTERCYCLE_GAP then
            tcnt  <= 0;
            state <= IDLE;
          else
            tcnt <= tcnt + 1;
          end if;

      end case;
    end if;
  end process;

  -- ===== Busy indication =====
  busy <= '1' when state /= IDLE else '0';

end architecture;



-- All example code has comments.
entity i82586_bus_model is
  generic (
    -- 8 MHz period for reference (not strictly required, but handy)
    G_TCLK          : time := 125 ns;

    -- ===== Datasheet windows (use MIN/TYP/MAX below) =====
    -- T33: S0/S1 valid delay after rising edge (pre-T1)
    G_T33_MIN       : time := 0 ns;
    G_T33_TYP       : time := 30 ns;
    G_T33_MAX       : time := 60 ns;

    -- T29: Address valid delay after start of T1 (falling edge)
    G_T29_MIN       : time := 0 ns;
    G_T29_TYP       : time := 30 ns;
    G_T29_MAX       : time := 55 ns;

    -- T30: AD bus floats after start of T2 (falling edge)
    G_T30_MIN       : time := 0 ns;
    G_T30_TYP       : time := 25 ns;
    G_T30_MAX       : time := 50 ns;

    -- Pick which corner we drive at: 0=MIN, 1=TYP, 2=MAX
    G_CORNER        : integer := 2;  -- default to MAX for safety

    -- Keep your older cycle params if you still want them
    G_T1_CYCLES     : natural := 1;
    G_T2_CYCLES     : natural := 1;
    G_T3_MIN_CYCLES : natural := 1;
    G_T4_CYCLES     : natural := 1;

    -- Status encodings, bus widths, etc. (unchanged)
    G_SCODE_MEM_RD  : std_logic_vector(1 downto 0) := "10";
    G_SCODE_MEM_WR  : std_logic_vector(1 downto 0) := "11";
    G_SCODE_IDLE    : std_logic_vector(1 downto 0) := "00";
    G_DATA_WIDTH    : positive := 16;
    G_ADDR_WIDTH    : positive := 20
  );
  port (
    clk_8m, rst_n   : in  std_logic;
    start, rw       : in  std_logic;
    addr_in         : in  std_logic_vector(G_ADDR_WIDTH-1 downto 0);
    wdata_in        : in  std_logic_vector(G_DATA_WIDTH-1 downto 0);
    busy, done      : out std_logic;
    rdata_out       : out std_logic_vector(G_DATA_WIDTH-1 downto 0);
    A_bus           : out std_logic_vector(G_ADDR_WIDTH-1 downto 0);
    S1, S0          : out std_logic;
    CS_n, RD_n, WR_n: out std_logic;
    D_bus           : inout std_logic_vector(G_DATA_WIDTH-1 downto 0);
    READY_n         : in  std_logic
  );
end entity;



architecture behav of i82586_bus_model is
  -- Return the selected delay for a spec window.
  function pick(min_t, typ_t, max_t : time; corner : integer) return time is
  begin
    case corner is
      when 0 => return min_t;        -- MIN
      when 1 => return typ_t;        -- TYP
      when others => return max_t;   -- MAX (default)
    end case;
  end function;

  -- Shorthand constants for this run (so we don’t recompute pick(...) all over)
  constant T33 : time := pick(G_T33_MIN, G_T33_TYP, G_T33_MAX, G_CORNER);
  constant T29 : time := pick(G_T29_MIN, G_T29_TYP, G_T29_MAX, G_CORNER);
  constant T30 : time := pick(G_T30_MIN, G_T30_TYP, G_T30_MAX, G_CORNER);

  -- Internal regs/signals (same as before) …
  -- svec, d_drive, d_out, rw_q, addr_q, etc.



  process(clk_8m, rst_n)
  begin
    if rst_n='0' then
      -- reset lines as before …
    elsif rising_edge(clk_8m) then
      done_q <= '0';

      case state is
        when IDLE =>
          -- Latch request on start
          if start='1' then
            rw_q    <= rw;
            addr_q  <= addr_in;
            wdata_q <= wdata_in;

            -- === T33: status S1:S0 valid some ns after this rising edge ===
            if rw='1' then
              -- READ status code after T33
              svec <= transport G_SCODE_MEM_RD after T33;   -- <<<< T33 applied
            else
              -- WRITE status code after T33
              svec <= transport G_SCODE_MEM_WR after T33;   -- <<<< T33 applied
            end if;

            -- We still *transition state* on the next falling edge -> T1
            state <= T1;
            tcnt  <= 0;
          end if;



    elsif falling_edge(clk_8m) then
      -- Falling edge marks the start of T1, T2, T3, T4 depending on state
      case state is
        when T1 =>
          -- Assert CS# immediately if you like; address has its own window.
          CS_n <= '0';

          -- === T29: address valid some ns after T1 start (this falling edge) ===
          A_bus <= transport addr_q after T29;              -- <<<< T29 applied

          -- Control strobes remain deasserted in T1; FSM cycle counting unchanged.



        when T2 =>
          -- T2 start: assert RD#/WR# immediately (cycle-accurate),
          -- but model the *multiplexed bus* turn-around with T30.
          if rw_q='1' then
            RD_n <= '0'; WR_n <= '1';
            d_drive <= '0';           -- we never drive on reads
          else
            RD_n <= '1'; WR_n <= '0';
            -- We are writing: put data up now; keep OE asserted until T30 expires
            d_out   <= wdata_q;
            d_drive <= '1';
          end if;

          -- === T30: AD bus goes Hi-Z after T2 start by 0..50 ns ===
          -- On a true AD[15:0] bus this means: stop driving address after T30.
          -- If you modeled a separate 'ad_oe', this is where you drop it.
          -- For simplicity, if A and D share the vector D_bus externally,
          -- you can release your "address drive" here:
          --   ad_oe <= transport '0' after T30;
          -- Below line shows the *idea*; adapt it to your AD muxing:
          --   A_bus_drive_enable <= transport '0' after T30;  -- <<<< T30 applied



        when T3 =>
          -- Wait-state handling identical to before; when READY_n deasserts:
          if (tcnt + 1 >= G_T3_MIN_CYCLES) and (READY_n='1') then
            if rw_q='1' then
              -- On READ, capture data sometime before T4 (use T8/T9 if you add them)
              rdata_q <= D_bus;
            end if;
            tcnt  <= 0;
            state <= T4;
          else
            tcnt <= tcnt + 1;
          end if;



