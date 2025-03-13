{$optimize -1}
{---------------------------------------------------------------}
{                                                               }
{  ORCA Code Generator Common                                   }
{                                                               }
{  This unit contains the command constants, types,             }
{  variables and procedures used throughout the code            }
{  generator, but which are not available to the compiler.      }
{                                                               }
{---------------------------------------------------------------}
{                                                               }
{  These routines are defined in the compiler, but used from    }
{  the code generator.                                          }
{                                                               }
{  Error - flag an error                                        }
{  CMalloc - Clear and allocate memory from a pool.             }
{  Malloc - Allocate memory from a pool.                        }
{                                                               }
{---------------------------------------------------------------}

unit CGC;

interface

{$LibPrefix '0/obj/'}

uses PCommon, CGI;

{$segment 'cg'}

const
                                        {Code Generation}
                                        {---------------}
   maxCBuff     =       191;            {length of constant buffer}

                                        {65816 native code generation}
                                        {----------------------------}
                                        {instruction modifier flags}
   shift8                 =      1;     {shift operand left 8 bits}
   shift16                =      2;     {shift operand left 16 bits}
   toolCall               =      4;     {generate a tool call}
   stringReference        =      8;     {generate a string reference}
   usertoolCall           =     16;     {generate a usertool call}
   isPrivate              =     32;     {is the label private?}
   constantOpnd           =     64;     {the absolute operand is a constant}
   localLab               =    128;     {the operand is a local lab}
   sub1                   =    256;     {subtract 1 from the operand}

   m_adc_abs              =    $6D;     {op code #s for 65816 instructions}
   m_adc_dir              =    $65;
   m_adc_imm              =    $69;
   m_adc_s                =    $63;
   m_and_abs              =    $2D;
   m_and_dir              =    $25;
   m_and_imm              =    $29;
   m_and_s                =    $23;
   m_asl_a                =    $0A;
   m_bcc                  =    $90;
   m_bcs                  =    $B0;
   m_beq                  =    $F0;
   m_bit_imm              =    $89;
   m_bmi                  =    $30;
   m_bne                  =    $D0;
   m_bpl                  =    $10;
   m_bra                  =    $80;
   m_brl                  =    $82;
   m_bvs                  =    $70;
   m_clc                  =    $18;
   m_cmp_abs              =    $CD;
   m_cmp_dir              =    $C5;
   m_cmp_dirX             =    $D5;
   m_cmp_imm              =    $C9;
   m_cmp_long             =    $CF;
   m_cmp_s                =    $C3;
   m_cop                  =    $02;
   m_cpx_abs              =    236;
   m_cpx_dir              =    228;
   m_cpx_imm              =    224;
   m_dea                  =     58;
   m_dec_abs              =    206;
   m_dec_absX             =    $DE;
   m_dec_dir              =    198;
   m_dec_dirX             =    214;
   m_dex                  =    202;
   m_dey                  =    136;
   m_eor_abs              =     77;
   m_eor_dir              =     69;
   m_eor_imm              =     73;
   m_eor_s                =     67;
   m_ina                  =     26;
   m_inc_abs              =    238;
   m_inc_absX             =    $FE;
   m_inc_dir              =    230;
   m_inc_dirX             =    246;
   m_inx                  =    232;
   m_iny                  =    200;
   m_jml                  =     92;
   m_jsl                  =     34;
   m_lda_abs              =    173;
   m_lda_absx             =    189;
   m_lda_dir              =    165;
   m_lda_dirx             =    181;
   m_lda_imm              =    169;
   m_lda_indl             =    167;
   m_lda_indly            =    183;
   m_lda_long             =    175;
   m_lda_longx            =    191;
   m_lda_s                =    163;
   m_ldx_abs              =    174;
   m_ldx_dir              =    166;
   m_ldx_imm              =    162;
   m_ldy_abs              =    172;
   m_ldy_absX             =    188;
   m_ldy_dir              =    164;
   m_ldy_dirX             =    180;
   m_ldy_imm              =    160;
   m_lsr_a                =     74;
   m_mvn                  =     84;
   m_ora_abs              =     13;
   m_ora_dir              =      5;
   m_ora_dirX             =     21;
   m_ora_imm              =      9;
   m_ora_long             =     15;
   m_ora_longX            =     31;
   m_ora_s                =      3;
   m_pea                  =    244;
   m_pei_dir              =    212;
   m_pha                  =     72;
   m_phb                  =    139;
   m_phd                  =     11;
   m_phk                  =    $4B;
   m_phx                  =    218;
   m_phy                  =     90;
   m_php                  =      8;
   m_pla                  =    104;
   m_plb                  =    171;
   m_pld                  =     43;
   m_plx                  =    250;
   m_ply                  =    122;
   m_plp                  =     40;
   m_rep                  =    194;
   m_rtl                  =    107;
   m_rts                  =     96;
   m_sbc_abs              =    237;
   m_sbc_dir              =    229;
   m_sbc_imm              =    233;
   m_sbc_s                =    227;
   m_sec                  =     56;
   m_sep                  =    226;
   m_sta_abs              =    141;
   m_sta_absX             =    157;
   m_sta_dir              =    133;
   m_sta_dirX             =    149;
   m_sta_indl             =    135;
   m_sta_indlY            =    151;
   m_sta_long             =    143;
   m_sta_longX            =    159;
   m_sta_s                =    131;
   m_stx_dir              =    134;
   m_stx_abs              =    142;
   m_sty_abs              =    140;
   m_sty_dir              =    132;
   m_sty_dirX             =    148;
   m_stz_abs              =    156;
   m_stz_absX             =    158;
   m_stz_dir              =    100;
   m_stz_dirX             =    116;
   m_tax                  =    170;
   m_tay                  =    168;
   m_tcd                  =     91;
   m_tcs                  =     27;
   m_tdc                  =    123;
   m_tsx                  =    $BA;
   m_txa                  =    138;
   m_txs                  =    $9A;
   m_txy                  =    155;
   m_tya                  =    152;
   m_tyx                  =    187;
   m_tsb_dir              =    $04;
   m_tsb_abs              =    $0C;
   m_tsc                  =     59;
   m_xba                  =    $EB;

   d_lab                  =    256;
   d_end                  =    257;
   d_bmov                 =    258;
   d_add                  =    259;
   d_pin                  =    260;
   d_wrd                  =    261;
   d_sym                  =    262;
   d_cns                  =    263;

   max_opcode             =    263;

type
                                        {pcode code generation}
                                        {---------------------}
   realrec = record                     {used to convert from real to in-SANE}
      itsReal: double;
      inSANE: packed array[1..10] of byte;
      inCOMP: packed array[1..8] of byte;
      end;

                                        {65816 native code generation}
                                        {----------------------------}
   labelptr = ^labelentry;              {pointer to a forward ref node}
   labelentry = record                  {forward ref node}
      addr: integer;
      next: labelptr;
      end;

   labelrec = record                    {label record}
      defined: boolean;                 {Note: form used in objout.asm}
      chain: labelptr;
      case boolean of
         true : (val: longint);
         false: (ival,hval: integer);
      end;

var
                                        {msc}
                                        {---}
   blkcnt: integer;                     {number of bytes in current segment}

                                        {buffers}
                                        {-------}
   cbufflen: 0..maxcbuff;               {number of bytes now in cbuff}
   segDisp: integer;                    {disp in the current segment}

                                        {65816 native code generation}
                                        {----------------------------}
   labeltab: array[0..maxlabel] of labelrec; {label table}
   localLabel: array[0..maxLocalLabel] of integer; {local variable label table}
   pc: longint;                         {program counter}

{---------------------------------------------------------------}

procedure CnvSX (rec: realrec); extern;

{ convert a real number to SANE extended format                 }
{                                                               }
{ parameters:                                                   }
{       rec - record containing the value to convert; also      }
{               has space for the result                        }

{---------------------------------------------------------------}

implementation

end.

{$append 'CGC.asm'}
