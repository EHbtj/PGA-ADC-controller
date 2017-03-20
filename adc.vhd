library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity ADC is
	port ( 
		-- クロックソース
	  clk      : in std_logic;
		
		-- SPI共通クロック
 		spi_sck  : out  std_logic;
		
		-- PGA (LTC6912-1)
		amp_cs   : out  std_logic := '1';
	  amp_shdn : out  std_logic := '0';
		
		-- ADC (LTC1407A-1)
		ad_conv  : out  std_logic := '0';
		spi_mosi : out  std_logic := '0';
		adc_out  : in   std_logic;
		
		-- デバッグ用
	  led      : out std_logic_vector(7 downto 0));	
end ADC;

architecture Behavioral of ADC is
	
	type state_type is (idle, amp_init, set_amp, read_adc);
	signal state : state_type := amp_init;
	
	type state_type_clock is (clock_on, clock_off);
	signal state_clock : state_type_clock := clock_off;
	
	-- PGAのゲインの設定値
	signal gain0 : std_logic_vector(3 downto 0) := "0001";
	signal gain1 : std_logic_vector(3 downto 0) := "0001";
	
	-- ADCの出力データバッファ
	signal data0_buf  : std_logic_vector(13 downto 0);
	signal data1_buf  : std_logic_vector(13 downto 0);
	
	-- PGAの設定終了フラグ
	signal set_end    : std_logic := '0';
	-- ADCの変換終了フラグ（いらないかも）
	signal conv_end		: std_logic := '0';
	
	-- カウンタ変数など
	signal counter    : integer range 0 to 34;
	signal cnt        : integer range 0 to 40 := 0;
	signal risingedge : std_logic := '1';
	signal clk_sample : std_logic := '0';
	
	begin

	-- クロックの分周（条件付き）
	clk_divider : process (clk)
	begin
		if (clk'event and clk = '1') then
			if (set_end = '0') then
				if (counter = 10) then
					risingedge <= not risingedge;
					clk_sample <= not clk_sample;
					counter <= 0;
				else
					counter <= counter + 1;
				end if;
			else 
				if (counter = 1) then
					risingedge <= not risingedge;
					clk_sample <= not clk_sample;
					counter <= 0;
				else
					counter <= counter + 1;
				end if;
			end if;
		end if; 
	end process;
	
	
	-- クロック制御
	clk_control : process(clk)
	begin
		if (clk'event and clk = '1') then
			case state_clock is
				when clock_on =>
					spi_sck <= clk_sample;
				when clock_off =>
					spi_sck <= '0';
			end case;
		end if;
	end process;

		
	main : process (clk)
	begin
		if (clk'event and clk = '1') then
			if (counter = 7 and risingedge = '1' and set_end = '0') then
				case state is
				
					when amp_init =>
						if (cnt < 2) then
							amp_shdn <= '0';
							cnt <= cnt + 1;
							state <= amp_init;
						elsif (2 <= cnt and cnt < 3) then
							amp_shdn <= '1';
							cnt <= cnt + 1;
							state <= amp_init;
						elsif (cnt = 3) then
							amp_shdn <= '0';
							cnt <= 0;
							state <= set_amp;
						end if;
						
					when set_amp =>
						amp_cs <= '0';
						amp_shdn <= '0';
						if (cnt < 4) then
							spi_mosi <= gain1(3 - cnt);
							cnt <= cnt + 1;
							state <= set_amp;
							state_clock <= clock_on;
						elsif (4 <= cnt and cnt < 8) then
							spi_mosi <= gain0(7 - cnt);
							cnt <= cnt + 1;
							state <= set_amp;
						elsif (cnt = 8) then
							cnt <= 0;
							spi_mosi <= '0';
							amp_cs <= '1';
							set_end <= '1';
							state <= idle;
						end if;
					
					when others =>
				end case;
			
			elsif (counter = 1 and risingedge = '1' and set_end = '1') then
				case state is
				
					when idle =>
						conv_end <= '0';
						if (cnt < 1) then
							ad_conv <= '1';
							cnt <= cnt + 1;
							state <= idle;
						elsif (cnt = 1) then
							ad_conv <= '0';
							cnt <= 0;
							state <= read_adc;
						end if;
	
					when read_adc =>
						if (cnt < 2) then
							-- Hi-Z
							cnt <= cnt + 1;
							state <= read_adc;
							state_clock <= clock_on;
							
						elsif (2 <= cnt and cnt < 16) then
							-- Data 0
							data0_buf(15 - cnt) <= adc_out;
							cnt <= cnt + 1;
							state <= read_adc;
							
						elsif (16 <= cnt and cnt < 18) then
							-- Hi-Z
							cnt <= cnt + 1;
							state <= read_adc;
							
						elsif (18 <= cnt and cnt < 32) then
							-- Data 1
							data1_buf(31 - cnt) <= adc_out;
							cnt <= cnt + 1;
							state <= read_adc;
							
						elsif (32 <= cnt and cnt < 34) then
							-- Hi-Z
							cnt <= cnt + 1;
							state <= read_adc;
							
						elsif (cnt = 34) then
							cnt <= 0;
							conv_end <= '1';
							state_clock <= clock_off;
							state <= idle;
						end if;
					
					when others =>	
				end case;
			end if;
		end if;
	end process;	

	func : process (clk)
	begin
		if (clk'event and clk = '1') then
			-- 13bit(MSB)は常に'1'で12bit目が符号ビット？ 出力信号は2の補数
			if (data0_buf(12) = '1') then
				-- data0_buf <= not data0_buf + '1';
				led <= data0_buf(11 downto 4);
			else
				led <= data0_buf(11 downto 4);
			end if;
		end if;
	end process;
	
end behavioral;