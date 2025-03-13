{$optimize -1}
{---------------------------------------------------------------}
{                                                               }
{  ORCA Native Code Generation                                  }
{                                                               }
{  This module of the code generator is called to generate      }
{  native code instructions.  The native code is optimized      }
{  and written to the object segment.                           }
{                                                               }
{  Externally available procedures:                             }
{                                                               }
{  EndSeg - close out the current segment                       }
{  GenNative - write a native code instruction to the output    }
{       file                                                    }
{  GenImplied - short form of GenNative - reduces code size     }
{  GenCall - short form of jsl to library subroutine - reduces  }
{       code size                                               }
{  GenLab - generate a label                                    }
{  InitFile - Set up the object file				}
{  InitNative - set up for a new segment			}
{  RefName - handle a reference to a named label                }
{                                                               }
{---------------------------------------------------------------}

unit Native;

interface

{$LibPrefix '0/obj/'}

uses PCommon, CGI, CGC, ObjOut;

{$segment 'CodeGen'}

{---------------------------------------------------------------}
   
procedure EndSeg;

{ close out the current segment                                 }


procedure GenNative (p_opcode: integer; p_mode: addressingMode;
                     p_operand: integer; p_name: pStringPtr; p_flags: integer);

{ write a native code instruction to the output file            }
{                                                               }
{ parameters:                                                   }
{       p_opcode - native op code                               }
{       p_mode - addressing mode                                }
{       p_operand - integer operand                             }
{       p_name - named operand                                  }
{       p_flags - operand modifier flags                        }


procedure GenImplied (p_opcode: integer);

{ short form of GenNative - reduces code size                   }
{                                                               }
{ parameters:                                                   }
{       p_code - operation code                                 }


procedure GenCall (callNum: integer);

{ short form of jsl to library subroutine - reduces code size   }
{                                                               }
{ parameters:                                                   }
{       callNum - subroutine # to generate a call for           }


procedure GenLab (lnum: integer);

{ generate a label                                              }
{                                                               }
{ parameters:                                                   }
{       lnum - label number                                     }


procedure InitFile (keepName: gsosOutStringPtr; keepFlag: integer; partial: boolean);

{ Set up the object file					}
{                                                               }
{ parameters:							}
{    keepName - name of the output file				}
{    keepFlag - keep status:					}
{       0 - don't keep the output				}
{       1 - create a new object module				}
{       2 - a .root already exists				}
{       3 - at least on .letter file exists			}
{    partial - is this a partial compile?			}
{								}
{ Note: Declared as extern in CGI.pas				}


procedure InitNative;

{ set up for a new segment					}


procedure LabelSearch (lab: integer; len, shift, disp: integer);

{ resolve a label reference                                     }
{                                                               }
{ parameters:                                                   }
{       lab - label number                                      }
{       len - # bytes for the generated code                    }
{       shift - shift factor                                    }
{       disp - disp past the label                              }
{                                                               }
{ Note 1: maxlabel is reserved for use as the start of the      }
{       string space                                            }
{ Note 2: negative length indicates relative branch             }
{ Note 3: zero length indicates 2 byte addr -1                  }


procedure RefName (lab: pStringPtr; disp, len, shift: integer);

{ handle a reference to a named label                           }
{                                                               }
{ parameters:                                                   }
{       lab - label name                                        }
{       disp - displacement past the label                      }
{       len - number of bytes in the reference                  }
{       shift - shift factor                                    }

{---------------------------------------------------------------}

implementation

const
   npeepSize = 128;			{native peephole optimizer window size}
   nMaxPeep = 4;			{max # instructions needed to opt.}

type
                                        {65816 native code generation}
                                        {----------------------------}
   npeepRange = 1..npeepsize;           {subrange for native code peephole opt.}

   nativeType = record                  {native code instruction}
      opcode: integer;                  {op code}
      mode: addressingMode;             {addressing mode}
      operand: integer;                 {operand value}
      name: pStringPtr;                  {operand label}
      flags: integer;                   {modifier flags}
      end;

   registerConditions = (regUnknown,regImmediate,regAbsolute,regLocal);
   registerType = record                {used to track register contents}
      condition: registerConditions;
      value: integer;
      lab: pStringPtr;
      flags: integer;
      end;

var
                                        {65816 native code generation}
                                        {----------------------------}
   longA,longI: boolean;                {register sizes}

                                        {I/O files}
                                        {---------}
   fname1, fname2: gsosOutString;	{file names}
   nextSuffix: char;                    {next suffix character to use}

                                        {native peephole optimization}
                                        {----------------------------}
   aRegister,                           {current register contents}
      xRegister,
      yRegister: registerType;
   didOne: boolean;                     {has an optimization been done?}
   nleadOpcodes: set of 0..max_opcode;  {instructions that can start an opt.}
   nstopOpcodes: set of 0..max_opcode;  {instructions not involved in opt.}
   npeep: array[npeepRange] of nativeType; {native peephole array}
   nnextspot: npeepRange;               {next empty spot in npeep}
   

procedure GenSymbols (sym: ptr; doGlobals: integer); extern;

{ generate the symbol table                                     }

{---------------------------------------------------------------}

procedure UpDate (lab: integer; labelValue: longint);

{ define a label						}
{								}
{ parameters:							}
{    lab - label number						}
{    labelValue - displacement in seg where label is located	}

var
   next,temp: labelptr;			{work pointers}

begin {UpDate}
if labeltab[lab].defined then
   Error(cge1)
else begin

   {define the label for future references}
   with labeltab[lab] do begin
      defined := true;
      val := labelValue;
      next := chain;
      end; {with}

   {resolve any forward references}
   if next <> nil then begin
      Purge;
      while next <> nil do begin
         segdisp := next^.addr;
         Out2(long(labelvalue).lsw);
         Out2(long(labelvalue).msw);
         blkcnt := blkcnt-4;
         temp := next;
         next := next^.next;
         end; {while}
      segdisp := blkcnt;
      end; {if}
   end; {else}
end; {UpDate}


procedure WriteNative (opcode: integer; mode: addressingMode; operand: integer;
                      name: pStringPtr; flags: integer);

{ write a native code instruction to the output file            }
{                                                               }
{ parameters:                                                   }
{       opcode - native op code                                 }
{       mode - addressing mode                                  }
{       operand - integer operand                               }
{       name - named operand                                    }
{       flags - operand modifier flags                          }

label 1;

type
   rkind = (k1,k2,k3);                  {cnv record types}

var
   ch: char;                            {temp storage for string constants}
   cns: realRec;                        {for converting reals to bytes}
   cnv: record                          {for converting double, real to bytes}
      case rkind of
         k1: (rval: real;);
         k2: (dval: double;);
         k3: (ival1,ival2,ival3,ival4: integer;);
      end;
   count: integer;                      {number of constants to repeat}
   i,j,k: integer;                      {loop variables}
   lsegDisp: integer;                   {for backtracking while writting the   }
                                        { debugger's symbol table              }
   lval: longint;                       {temp storage for long constant}
   nptr: pStringPtr;                    {pointer to a name}
   sptr: pStringPtr;                    {pointer to a string constant}


   procedure GenImmediate1;

   { generate a one byte immediate operand                      }

   begin {GenImmediate1}
   if (flags & stringReference) <> 0 then begin
      Purge;
      Out(235); Out(1);                 {one byte expression}
      Out(128);                         {current location ctr}
      Out(129); Out2(-16); Out2(-1);    {-16}
      Out(7);                           {bit shift}
      Out(0);                           {end of expr}
      pc := pc+1;
      end {if}
   else if (flags & localLab) <> 0 then
      LabelSearch(long(name).lsw, 1, ord(odd(flags div shift16))*16, operand)
   else if (flags & shift16) <> 0 then
      RefName(name, operand, 1, -16)
   else
      CnOut(operand);
   end; {GenImmediate1}


   procedure GenImmediate2;

   { generate a two byte immediate operand                      }

   begin {GenImmediate2}
   if (flags & stringReference) <> 0 then begin
      Purge;
      Out(235); Out(2);
      LabelSearch(maxLabel, 2, 0, 0);
      if operand <> 0 then begin
         Out(129);
         Out2(operand); Out2(0);
         Out(1);
         end; {if}
      if (flags & shift16) <> 0 then begin
         Out(129);
         Out2(-16); Out2(-1);
         Out(7);
         end; {if}
      Out(0);
      end {if}
   else if (flags & shift8) <> 0 then
      RefName(name, operand, 2, -8)
   else if (flags & localLab) <> 0 then
      LabelSearch(long(name).lsw, 2, ord(odd(flags div shift16))*16, operand)
   else if (flags & shift16) <> 0 then
      RefName(name, operand, 2, -16)
   else if name = nil then
      CnOut2(operand)
   else
      RefName(name, operand, 2, 0);
   end; {GenImmediate2}


   procedure DefGlobal (private: integer);

   { define a global label                                      }
   {                                                            }
   { parameters:                                                }
   {    private - private flag                                  }

   var
      i: integer;                       {loop variable}

   begin {DefGlobal}
   Purge;
   Out(230);                            {global label definition}
   Out(ord(name^[0]));                  {write label name}
   for i := 1 to ord(name^[0]) do
      Out(ord(name^[i]));
   Out2(0);				{length attribute}
   Out(ord('N'));                       {type attribute: other directive}
   Out(private);                        {private or global?}
   end; {DefGlobal}


begin {WriteNative}
{ writeln('WriteNative: ',opcode:4, ', mode=', ord(mode):1,
   ' operand=', operand:1);      {debug}
case mode of

   implied:
      CnOut(opcode);

   immediate: begin
      if opcode = d_bmov then
         GenImmediate1
      else begin
         if opcode = m_and_imm then
            if not longA then
               if operand = 255 then
                  goto 1;
         CnOut(opcode);
         if opcode = m_pea then
            GenImmediate2
         else if opcode in
            [m_adc_imm,m_and_imm,m_cmp_imm,m_eor_imm,m_lda_imm,m_ora_imm,
             m_sbc_imm,m_bit_imm] then
               if longA then
                 GenImmediate2
              else
                 GenImmediate1
         else if opcode in [m_rep,m_sep,m_cop] then begin
            GenImmediate1;
            if opcode = m_rep then begin
               if odd(operand div 32) then longA := true;
               if odd(operand div 16) then longI := true;
               end {if}
            else if opcode = m_sep then begin
               if odd(operand div 32) then longA := false;
               if odd(operand div 16) then longI := false;
               end; {else}
            end {else}
         else
            if longI then
               GenImmediate2
            else
               GenImmediate1;
         end; {else}
      end;

   longabs: begin
      CnOut(opcode);
      isJSL := opcode = m_jsl;          {allow for dynamic segs}
      if name = nil then
         if odd(flags div toolCall) then begin
            CnOut2(0);
            CnOut($E1);
            end {if}
         else if odd(flags div userToolCall) then begin
            CnOut2(8);
            CnOut($E1);
            end {else if}
         else
            LabelSearch(operand, 3, 0, 0)
      else
         RefName(name, operand, 3, 0);
      isJSL := false;
      end;

   longabsolute: begin
      if opcode <> d_add then begin
         CnOut(opcode);
         i := 3;
         end {if}
      else
         i := 4;
      if (flags & localLab) <> 0 then
         LabelSearch(long(name).lsw, i, 0, operand)
      else if (flags & constantOpnd) <> 0 then begin
         lval := ord4(name);
         CnOut2(long(lval).lsw);
         if opcode = d_add then
            CnOut2(long(lval).msw)
         else
            CnOut(long(lval).msw);
         end {else if}
      else if name <> nil then
         RefName(name, operand, i, 0)
      else begin
         CnOut2(operand);
         CnOut(0);
         if opcode = d_add then
            CnOut(0);
         end; {else}
      end;

   absolute: begin
      if opcode <> d_add then
         CnOut(opcode);
      if (flags & localLab) <> 0 then
         LabelSearch(long(name).lsw, 2, 0, operand)
      else if name <> nil then
         RefName(name, operand, 2, 0)
      else if (flags & constantOpnd) <> 0 then
         CnOut2(operand)
      else
         LabelSearch(operand, 2, 0, 0);
      end;

   direct: begin
      if opcode <> d_add then
         CnOut(opcode);
      if (flags & localLab) <> 0 then
         LabelSearch(long(name).lsw, 1, 0, operand)
      else if name <> nil then
         RefName(name, operand, 1, 0)
      else
         CnOut(operand);
      end;

   longrelative: begin
      CnOut(opcode);
      LabelSearch(operand, -2, 0, 0);
      end;

   relative: begin
      CnOut(opcode);
      LabelSearch(operand, -1, 0, 0);
      end;

   gnrLabel:
      if name = nil then
         UpDate(operand, pc+cbufflen)
      else begin
         DefGlobal((flags >> 5) & 1);
         if operand <> 0 then begin
            Out(241);
            Out2(operand);
            Out2(0);
            pc := pc+operand;
            end; {if}
        end; {else}

   gnrSpace:
      if operand <> 0 then begin
         Out(241);
         Out2(operand);
         Out2(0);
         pc := pc+operand;
         end; {if}

   gnrConstant: begin
      if icptr(name)^.optype = cgString then
         count := 1
      else
         count := icptr(name)^.q;
      for i := 1 to count do
         case icptr(name)^.optype of
            cgByte,cgUByte      : CnOut(icptr(name)^.r);
            cgWord,cgUWord      : CnOut2(icptr(name)^.r);
            cgLong,cgULong      : begin
                                  lval := icptr(name)^.lval;
                                  CnOut2(long(lval).lsw);
                                  CnOut2(long(lval).msw);
                                  end;
            cgReal              : begin
                                  cnv.rval := icptr(name)^.rval;
                                  CnOut2(cnv.ival1);
                                  CnOut2(cnv.ival2);
                                  end;
            cgDouble            : begin
                                  cnv.dval := icptr(name)^.rval;
                                  CnOut2(cnv.ival1);
                                  CnOut2(cnv.ival2);
                                  CnOut2(cnv.ival3);
                                  CnOut2(cnv.ival4);
                                  end;
            cgString            : begin
                                  sptr := icptr(name)^.str;
                                  for j := 1 to length(sptr^) do
                                     CnOut(ord(sPtr^[j]));
                                  end;
            otherwise           : Error(cge1);
            end; {case}
      end;

   genAddress: begin
      if opcode < 256 then
         CnOut(opcode);
      if (flags & stringReference) <> 0 then begin
         Purge;
         Out(235);
         Out(2);
         LabelSearch(maxLabel,2,0,0);
         if operand <> 0 then begin
            Out(129);
            Out2(operand);
            Out2(0);
            Out(1);
            end; {if}
         if (flags & shift16) <> 0 then begin
            Out(129);
            Out2(-16);
            Out2(-1);
            Out(7);
            end; {if}
         Out(0);
         end {if}
      else if operand = 0 then begin
         CnOut(0);
         CnOut(0);
         end {else if}
      else if (flags & shift16) <> 0 then
         if longA then
            LabelSearch(operand, 2, 16, 0)
         else
            LabelSearch(operand, 1, 16, 0)
      else if (flags & sub1) <> 0 then
         LabelSearch(operand, 0, 0, 0)
      else  
         LabelSearch(operand, 2, 0, 0);
      end;

   special:
      if opcode = d_pin then begin
         segDisp := 36;
         out2(long(pc).lsw+cBuffLen);
         blkCnt := blkCnt-2;
         segDisp := blkCnt;
         end {if}
      else if opcode = d_sym then begin
         CnOut(m_cop);
         CnOut(5);
         Purge;
         lsegDisp := segDisp+1;
         CnOut2(0);
         symLength := 0;
         GenSymbols(pointer(name), operand);
         segDisp := lSegDisp;
         out2(symLength);
         blkCnt := blkCnt-2;
         segDisp := blkCnt;
         end {else if}
      else {d_wrd}
         CnOut2(operand);

   otherwise: Error(cge1);

   end; {case}
1:
end; {WriteNative}


procedure CheckRegisters(p_opcode: integer; p_mode: addressingMode;
                    p_operand: integer; p_name: pStringPtr; p_flags: integer);

{ write a native code instruction to the output file            }
{                                                               }
{ parameters:                                                   }
{       p_opcode - native op code                               }
{       p_mode - addressing mode                                }
{       p_operand - integer operand                             }
{       p_name - named operand                                  }
{       p_flags - operand modifier flags                        }

label 1,2;

begin {CheckRegisters}
case p_opcode of
   m_adc_abs,m_adc_dir,m_adc_imm,m_adc_s,m_and_abs,m_and_dir,m_and_imm,
   m_and_s,m_asl_a,m_dea,m_eor_abs,m_eor_dir,m_eor_imm,m_eor_s,m_lda_absx,
   m_lda_dirx,m_lda_indl,m_lda_indly,m_lda_longx,m_lda_s,m_lsr_a,m_ora_abs,
   m_ora_dir,m_ora_dirX,m_ora_imm,m_ora_long,m_ora_longX,m_ora_s,m_pla,
   m_sbc_abs,m_sbc_dir,m_sbc_imm,m_sbc_s,m_tdc,m_tsc,m_tsb_dir,m_tsb_abs:
      aRegister.condition := regUnknown;

   m_ldy_absX,m_ldy_dirX,m_ply:
      yRegister.condition := regUnknown;

   m_plx:
      xRegister.condition := regUnknown;

   m_bcc,m_bcs,m_beq,m_bmi,m_bne,m_bpl,m_bra,m_brl,m_bvs,m_clc,m_cmp_abs,
   m_cmp_dir,m_cmp_imm,m_cmp_s,m_cpx_imm,m_jml,m_pha,m_phb,m_phd,
   m_phx,m_phy,m_plb,m_pld,m_rtl,m_rts,m_sec,m_sta_absX,
   m_sta_dir,m_sta_dirX,m_sta_indl,m_sta_indlY,m_sta_longX,
   m_sta_s,m_stx_dir,m_sty_dir,m_sty_dirX,m_stz_abs,m_stz_absX,
   m_stz_dir,m_stz_dirX,m_tcs,m_tcd,d_add,d_pin,m_pei_dir,m_cpx_abs,
   m_cpx_dir,m_cmp_dirx,m_php,m_plp,m_cop,d_wrd:   ;

   m_pea: begin
      if aRegister.condition = regImmediate then
         if aRegister.value = p_operand then
            if aRegister.lab = p_name then
               if aRegister.flags = p_flags then
        	  if longA then begin
        	     p_opcode := m_pha;
        	     p_mode := implied;
        	     goto 2;
        	     end; {if}
      if longI then begin
	 if xRegister.condition = regImmediate then
            if xRegister.value = p_operand then
               if xRegister.lab = p_name then
        	  if xRegister.flags = p_flags then begin
        	     p_opcode := m_phx;
        	     p_mode := implied;
        	     goto 2;
        	     end; {if}
	 if yRegister.condition = regImmediate then
            if yRegister.value = p_operand then
               if yRegister.lab = p_name then
        	  if yRegister.flags = p_flags then begin
        	     p_opcode := m_phy;
        	     p_mode := implied;
        	     goto 2;
        	     end; {if}
         end; {if}
      end;

   m_dec_abs,m_inc_abs,m_sta_abs,m_stx_abs,m_sty_abs,m_sta_long: begin
      if aRegister.condition = regAbsolute then
         if aRegister.lab = p_name then
            if aRegister.value = p_operand then
               if not (p_opcode in [m_sta_abs,m_sta_long]) then
                  aRegister.condition := regUnknown;
      if xRegister.condition = regAbsolute then
         if xRegister.lab = p_name then
            if xRegister.value = p_operand then
               if p_opcode <> m_stx_abs then
                  xRegister.condition := regUnknown;
      if yRegister.condition = regAbsolute then
         if yRegister.lab = p_name then
            if yRegister.value = p_operand then
               if p_opcode <> m_sty_abs then
                  yRegister.condition := regUnknown;
      end;

   m_dec_dir,m_dec_dirX,m_inc_dir,m_inc_dirX: begin
      if aRegister.condition = regLocal then
         if aRegister.value = p_operand then
            aRegister.condition := regUnknown;
      if xRegister.condition = regLocal then
         if xRegister.value = p_operand then
            xRegister.condition := regUnknown;
      if yRegister.condition = regLocal then
         if yRegister.value = p_operand then
            yRegister.condition := regUnknown;
      end;

   m_dex:
      if xRegister.condition = regImmediate then
         xRegister.value := xRegister.value-1
      else
         xRegister.condition := regUnknown;

   m_dey:
      if yRegister.condition = regImmediate then
         yRegister.value := yRegister.value-1
      else
         yRegister.condition := regUnknown;

   m_ina:
      if aRegister.condition = regImmediate then
         aRegister.value := aRegister.value+1
      else
         aRegister.condition := regUnknown;

   m_inx:
      if xRegister.condition = regImmediate then
         xRegister.value := xRegister.value+1
      else
         xRegister.condition := regUnknown;

   m_iny:
      if yRegister.condition = regImmediate then
         yRegister.value := yRegister.value+1
      else
         yRegister.condition := regUnknown;

   otherwise,
   m_jsl,m_mvn,m_rep,m_sep,d_lab,d_end,d_bmov,d_cns: begin
      aRegister.condition := regUnknown;
      xRegister.condition := regUnknown;
      yRegister.condition := regUnknown;
      end;

   m_lda_abs,m_lda_long: begin
      if (aRegister.condition = regAbsolute) and
         (aRegister.value = p_operand) and
         (aRegister.lab = p_name) then
         goto 1
      else if longA = longI then begin
         if (xRegister.condition = regAbsolute) and
            (xRegister.value = p_operand) and
            (xRegister.lab = p_name) then begin
            p_opcode := m_txa;
            p_mode := implied;
            aRegister := xRegister;
            goto 2;
            end {if}
         else if (yRegister.condition = regAbsolute) and
            (yRegister.value = p_operand) and
            (yRegister.lab = p_name) then begin
            p_opcode := m_tya;
            p_mode := implied;
            aRegister := yRegister;
            goto 2;
            end; {else if}
         end;
      aRegister.condition := regAbsolute;
      aRegister.value := p_operand;
      aRegister.lab := p_name;
      aRegister.flags := p_flags;
      end;

   m_lda_dir: begin
      if (aRegister.condition = regLocal) and
         (aRegister.value = p_operand) then
         goto 1
      else if longA = longI then begin
         if (xRegister.condition = regLocal) and
            (xRegister.value = p_operand) then begin
            p_opcode := m_txa;
            p_mode := implied;
            aRegister := xRegister;
            goto 2;
            end {if}
         else if (yRegister.condition = regLocal) and
            (yRegister.value = p_operand) then begin
            p_opcode := m_tya;
            p_mode := implied;
            aRegister := yRegister;
            goto 2;
            end; {else if}
         end; {else if}
      aRegister.condition := regLocal;
      aRegister.value := p_operand;
      aRegister.flags := p_flags;
      end;

   m_lda_imm: begin
      if (aRegister.condition = regImmediate) and
         (aRegister.value = p_operand) and
         (aRegister.lab = p_name) and
         (aRegister.flags = p_flags) then
         goto 1
      else if longA = longI then begin
         if (xRegister.condition = regImmediate) and
            (xRegister.value = p_operand) and
            (xRegister.lab = p_name) and
            (xRegister.flags = p_flags) then begin
            p_opcode := m_txa;
            p_mode := implied;
            aRegister := xRegister;
            goto 2;
            end {if}
         else if (yRegister.condition = regImmediate) and
            (yRegister.value = p_operand) and
            (yRegister.lab = p_name) and
            (yRegister.flags = p_flags) then begin
            p_opcode := m_tya;
            p_mode := implied;
            aRegister := yRegister;
            goto 2;
            end; {else if}
         end; {else if}
      if (aRegister.condition = regImmediate) and
         (aRegister.lab = p_name) and
         (aRegister.flags = p_flags) then
         if aRegister.value = (p_operand + 1) then begin
            p_opcode := m_dea;
            p_mode := implied;
            aRegister.value := p_operand;
            goto 2;
            end {if}   
         else if aRegister.value = (p_operand - 1) then begin
            p_opcode := m_ina;
            p_mode := implied;
            aRegister.value := p_operand;
            goto 2;
            end; {else if}
      aRegister.condition := regImmediate;
      aRegister.value := p_operand;
      aRegister.flags := p_flags;
      aRegister.lab := p_name;
      end;

   m_ldx_abs: begin
      if (xRegister.condition = regAbsolute) and
         (xRegister.value = p_operand) and
         (xRegister.lab = p_name) then
         goto 1
      else if (aRegister.condition = regAbsolute) and
         (aRegister.value = p_operand) and
         (aRegister.lab = p_name) and
         (longA = longI) then begin
         p_opcode := m_tax;
         p_mode := implied;
         xRegister := aRegister;
         end {else if}
      else if (yRegister.condition = regAbsolute) and
         (yRegister.value = p_operand) and
         (yRegister.lab = p_name) then begin
         p_opcode := m_tyx;
         p_mode := implied;
         xRegister := yRegister;
         end {else if}
      else begin
         xRegister.condition := regAbsolute;
         xRegister.value := p_operand;
         xRegister.lab := p_name;
         xRegister.flags := p_flags;
         end; {else}
      end;

   m_ldx_dir: begin
      if (xRegister.condition = regLocal) and
         (xRegister.value = p_operand) then
         goto 1
      else if (aRegister.condition = regLocal) and
         (aRegister.value = p_operand) and
         (longA = longI) then begin
         p_opcode := m_tax;
         p_mode := implied;
         xRegister := aRegister;
         end {else if}
      else if (yRegister.condition = regLocal) and
         (yRegister.value = p_operand) then begin
         p_opcode := m_tyx;
         p_mode := implied;
         xRegister := yRegister;
         end {else if}
      else begin
         xRegister.condition := regLocal;
         xRegister.value := p_operand;
         xRegister.flags := p_flags;
         end; {else}
      end;

   m_ldx_imm: begin
      if (xRegister.condition = regImmediate) and
         (xRegister.value = p_operand) and
         (xRegister.lab = p_name) and
         (xRegister.flags = p_flags) then
         goto 1
      else if (aRegister.condition = regImmediate) and
         (aRegister.value = p_operand) and
         (longA = longI) and
         (aRegister.lab = p_name) and
         (aRegister.flags = p_flags) then begin
         p_opcode := m_tax;
         p_mode := implied;
         xRegister := aRegister;
         end {else}
      else if (yRegister.condition = regImmediate) and
         (yRegister.value = p_operand) and
         (yRegister.lab = p_name) and
         (yRegister.flags = p_flags) then begin
         p_opcode := m_tyx;
         p_mode := implied;
         xRegister := yRegister;
         end {else if}
      else begin
	 if (xRegister.condition = regImmediate) and
            (xRegister.lab = p_name) and
            (xRegister.flags = p_flags) then
            if xRegister.value = (p_operand + 1) then begin
               p_opcode := m_dex;
               p_mode := implied;
               xRegister.value := p_operand;
               goto 2;
               end {if}   
            else if xRegister.value = (p_operand - 1) then begin
               p_opcode := m_inx;
               p_mode := implied;
               xRegister.value := p_operand;
               goto 2;
               end; {else if}
         xRegister.condition := regImmediate;
         xRegister.value := p_operand;
         xRegister.flags := p_flags;
         xRegister.lab := p_name;
         end; {else}
      end;

   m_ldy_abs: begin
      if (yRegister.condition = regAbsolute) and
         (yRegister.value = p_operand) and
         (yRegister.lab = p_name) then
         goto 1
      else if (aRegister.condition = regAbsolute) and
         (aRegister.value = p_operand) and
         (aRegister.lab = p_name) and
         (longA = longI) then begin
         p_opcode := m_tay;
         p_mode := implied;
         yRegister := aRegister;
         end {else if}
      else if (xRegister.condition = regAbsolute) and
         (xRegister.value = p_operand) and
         (xRegister.lab = p_name) then begin
         p_opcode := m_txy;
         p_mode := implied;
         yRegister := xRegister;
         end {else if}
      else begin
         yRegister.condition := regAbsolute;
         yRegister.value := p_operand;
         yRegister.lab := p_name;
         yRegister.flags := p_flags;
         end; {else}
      end;

   m_ldy_dir: begin
      if (yRegister.condition = regLocal) and
         (yRegister.value = p_operand) then
         goto 1
      else if (aRegister.condition = regLocal) and
         (aRegister.value = p_operand) and
         (longA = longI) then begin
         p_opcode := m_tay;
         p_mode := implied;
         yRegister := aRegister;
         end {else if}
      else if (xRegister.condition = regLocal) and
         (xRegister.value = p_operand) then begin
         p_opcode := m_txy;
         p_mode := implied;
         yRegister := xRegister;
         end {else if}
      else begin
         yRegister.condition := regLocal;
         yRegister.value := p_operand;
         yRegister.flags := p_flags;
         end; {else}
      end;

   m_ldy_imm: begin
      if (yRegister.condition = regImmediate) and
         (yRegister.value = p_operand) and
         (yRegister.lab = p_name) and
         (yRegister.flags = p_flags) then
         goto 1
      else if (aRegister.condition = regImmediate) and
         (aRegister.value = p_operand) and
         (aRegister.flags = p_flags) and
         (aRegister.lab = p_name) and
         (longA = longI) then begin
         p_opcode := m_tay;
         p_mode := implied;
         yRegister := aRegister;
         end {else if}
      else if (xRegister.condition = regImmediate) and
         (xRegister.value = p_operand) and
         (xRegister.lab = p_name) and
         (xRegister.flags = p_flags) then begin
         p_opcode := m_txy;
         p_mode := implied;
         yRegister := xRegister;
         end {else if}
      else begin
	 if (yRegister.condition = regImmediate) and
            (yRegister.lab = p_name) and
            (yRegister.flags = p_flags) then
            if yRegister.value = (p_operand + 1) then begin
               p_opcode := m_dey;
               p_mode := implied;
               yRegister.value := p_operand;
               goto 2;
               end {if}   
            else if yRegister.value = (p_operand - 1) then begin
               p_opcode := m_iny;
               p_mode := implied;
               yRegister.value := p_operand;
               goto 2;
               end; {else if}
         yRegister.condition := regImmediate;                   
         yRegister.value := p_operand;
         yRegister.flags := p_flags;
         yRegister.lab := p_name;
         end; {else}
      end;

   m_tax: begin
      if aRegister.condition <> regUnknown then
         if aRegister.condition = xRegister.condition then
            if aRegister.value = xRegister.value then
               if aRegister.flags = xRegister.flags then
                  if aRegister.condition <> regAbsolute then
                     goto 1
                  else if aRegister.lab = xRegister.lab then
                     goto 1;
      xRegister := aRegister;
      end;

   m_tay: begin
      if aRegister.condition <> regUnknown then
         if aRegister.condition = yRegister.condition then
            if aRegister.value = yRegister.value then
               if aRegister.flags = yRegister.flags then
                  if aRegister.condition <> regAbsolute then
                     goto 1
                  else if aRegister.lab = yRegister.lab then
                     goto 1;
      yRegister := aRegister;
      end;

   m_txa: begin
      if xRegister.condition <> regUnknown then
         if xRegister.condition = aRegister.condition then
            if xRegister.value = aRegister.value then
               if xRegister.flags = aRegister.flags then
                  if xRegister.condition <> regAbsolute then
                     goto 1
                  else if xRegister.lab = aRegister.lab then
                     goto 1;
      aRegister := xRegister;
      end;

   m_txy: begin
      if xRegister.condition <> regUnknown then
         if xRegister.condition = yRegister.condition then
            if xRegister.value = yRegister.value then
               if xRegister.flags = yRegister.flags then
                  if xRegister.condition <> regAbsolute then
                     goto 1
                  else if xRegister.lab = yRegister.lab then
                     goto 1;
      yRegister := xRegister;
      end;

   m_tya: begin
      if yRegister.condition <> regUnknown then
         if yRegister.condition = aRegister.condition then
            if yRegister.value = aRegister.value then
               if yRegister.flags = aRegister.flags then
                  if yRegister.condition <> regAbsolute then
                     goto 1
                  else if yRegister.lab = aRegister.lab then
                     goto 1;
      aRegister := yRegister;
      end;

   m_tyx: begin
      if yRegister.condition <> regUnknown then
         if yRegister.condition = xRegister.condition then
            if yRegister.value = xRegister.value then
               if yRegister.flags = xRegister.flags then
                  if yRegister.condition <> regAbsolute then
                     goto 1
                  else if yRegister.lab = xRegister.lab then
                     goto 1;
      xRegister := yRegister;
      end;
   end; {case}
2:
WriteNative(p_opcode, p_mode, p_operand, p_name, p_flags);
1:
end; {CheckRegisters}


procedure Remove (ns: integer); extern;

{ Remove the instruction ns from the peephole array             }
{                                                               }
{ parameters:                                                   }
{       ns - index of the instruction to remove                 }


function Short (n, lab: integer): boolean; extern;

{ see if a label is within range of a one-byte relative branch  }
{                                                               }
{ parameters:                                                   }
{       n - index to branch instruction                         }
{       lab - label number                                      }

{---------------------------------------------------------------}

procedure EndSeg;

{ close out the current segment                                 }

var
   i: integer;

begin {EndSeg}
Purge;                                  {dump constant buffer}
if stringsize <> 0 then begin           {define string space}
   UpDate(maxLabel, pc);                {define the local label for the string space}
   for i := 1 to stringsize do
      CnOut(ord(stringspace[i]));
   Purge;
   end; {if}
Out(0);                                 {end the segment}
segDisp := 8;                           {update header}
Out2(long(pc).lsw);
Out2(long(pc).msw);
blkcnt := blkcnt-4;                     {purge the segment to disk}
segDisp := blkcnt;
CloseSeg;
end; {EndSeg}


procedure GenNative {p_opcode: integer; p_mode: addressingMode;
                     p_operand: integer; p_name: pStringPtr; p_flags: integer};

{ write a native code instruction to the output file            }
{                                                               }
{ parameters:                                                   }
{       p_opcode - native op code                               }
{       p_mode - addressing mode                                }
{       p_operand - integer operand                             }
{       p_name - named operand                                  }
{       p_flags - operand modifier flags                        }

var
   done: boolean;                       {loop termination}
   llongA: boolean;                     {for tracking A size during opt.}
   i: integer;                          {index}
   op: integer;                         {temp storage for opcode}


   procedure Purge;

   { Empty the peephole array                                   }

   begin {Purge}
   while nnextSpot > 1 do begin
      if registers then
         CheckRegisters(npeep[1].opcode, npeep[1].mode, npeep[1].operand,
            npeep[1].name, npeep[1].flags)
      else
         WriteNative(npeep[1].opcode, npeep[1].mode, npeep[1].operand,
            npeep[1].name, npeep[1].flags);
      Remove(1);
      end; {while}
   end; {Purge}


   procedure Optimize(ns: integer; longA: boolean);

   { Optimize the instruction starting at ns                    }
   {                                                            }
   { parameters:                                                }
   {    ns - index of instruction  to check for optimization    }
   {    longA - is the accumulator long?                        }

   label 1;

   var
      tn: nativeType;			{temp operation}


      function ASafe (ns: integer): boolean;

      { See if it is safe to skip loading the A register        }
      {                                                         }
      { parameters:                                             }
      {    ns - starting index                                  }

      label 1;

      var
         i: integer;                    {loop variable}
         opcode: integer;               {copy of current op code}

      begin {ASafe}
      ASafe := false;
      for i := ns to nnextSpot-1 do begin
         opcode := npeep[i].opcode;
         if opcode in
            [m_bcc,m_bcs,m_beq,m_bmi,m_bne,m_bpl,m_bra,m_brl,m_bvs,m_jml,m_jsl,
             m_lda_abs,m_lda_absx,m_lda_dir,m_lda_dirx,m_lda_imm,m_lda_indl,
             m_lda_indly,m_lda_long,m_lda_longx,m_lda_s,m_mvn,m_pla,m_rtl,
             m_rts,m_tdc,m_txa,m_tya,m_tsc,d_end,d_bmov,d_add,d_pin,d_wrd,
             d_sym,d_cns] then begin
            ASafe := true;
            goto 1;
            end {if}
         else if opcode in
            [m_adc_abs,m_adc_dir,m_adc_imm,m_adc_s,m_and_abs,m_and_dir,
             m_and_imm,m_and_s,m_asl_a,m_cmp_abs,m_cmp_dir,m_cmp_dirX,m_cmp_imm,
             m_cmp_long,m_cmp_s,m_dea,m_eor_abs,m_eor_dir,m_eor_imm,m_eor_s,
             m_ina,m_lda_abs,m_lda_absx,m_lda_dir,m_lda_dirx,m_lda_imm,
             m_lda_indl,m_lda_indly,m_lda_long,m_lda_longx,m_lda_s,m_lsr_a,
             m_ora_abs,m_ora_dir,m_ora_dirX,m_ora_imm,m_ora_long,m_ora_longX,m_ora_s,
             m_pha,m_sbc_abs,m_sbc_dir,m_sbc_imm,m_sbc_s,m_sta_abs,m_sta_absX,
             m_sta_dir,m_sta_dirX,m_sta_indl,m_sta_indlY,m_sta_long,m_sta_longX,
             m_sta_s,m_tax,m_tay,m_tcd,m_tcs,m_xba,m_tsb_dir,m_tsb_abs] then
            goto 1;
         end; {for}
1:
      end; {ASafe}


      function SignExtension (ns: integer): boolean;

      { See if the pattern is a sugn extension			}
      {								}
      { Parameters:						}
      {    ns - start of suspected pattern			}
      {								}
      { Returns: true for a sign extension, else false		}

      begin {SignExtension}
      SignExtension := false;
      if npeep[ns].opcode = m_ldx_imm then
         if npeep[ns].operand = 0 then
            if npeep[ns+1].opcode = m_tay then
               if npeep[ns+2].opcode = m_bpl then
                  if npeep[ns+3].opcode = m_dex then
                     SignExtension := true;
      end; {SignExtension}


   begin {Optimize}
   with npeep[ns] do
      case opcode of

         m_and_imm:
            if npeep[ns+1].opcode = m_and_imm then begin
               operand := operand & npeep[ns+1].operand;
               Remove(ns+1);
               end; {if}

         m_asl_a:
            if npeep[ns+1].opcode = m_tay then
               if npeep[ns+2].opcode = m_iny then
                  if npeep[ns+3].opcode = m_iny then begin
                     opcode := m_ina;
                     npeep[ns+1].opcode := m_asl_a;
                     npeep[ns+2].opcode := m_tay;
                     Remove(ns+3);
                     end; {if}

         m_bcs,m_beq,m_bne,m_bmi,m_bpl,m_bcc:
            if npeep[ns+2].opcode = d_lab then
               if npeep[ns+2].operand = operand then
                  if npeep[ns+1].opcode = m_brl then begin
                     if Short(ns,npeep[ns+1].operand) then begin
                        operand := npeep[ns+1].operand;
                        Remove(ns+1);
                        if opcode = m_bcs then
                           opcode := m_bcc
                        else if opcode = m_beq then
                           opcode := m_bne
                        else if opcode = m_bne then
                           opcode := m_beq
                        else if opcode = m_bmi then
                           opcode := m_bpl
                        else if opcode = m_bcc then
                           opcode := m_bcs
                        else
                           opcode := m_bmi;
                        end; {if}
                     end {if m_brl}
                  else if npeep[ns+1].opcode = m_bra then begin
                     operand := npeep[ns+1].operand;
                     Remove(ns+1); Remove(ns+1);
                     if opcode = m_bcs then
                        opcode := m_bcc
                     else if opcode = m_beq then
                        opcode := m_bne
                     else if opcode = m_bne then
                        opcode := m_beq
                     else if opcode = m_bmi then
                        opcode := m_bpl
                     else if opcode = m_bcc then
                        opcode := m_bcs
                     else
                        opcode := m_bmi;
                     end; {else if m_bra}

         m_brl:
            if Short(ns,operand) then begin
               opcode := m_bra;
               mode := relative;
               didOne := true;
               end; {if}

         m_bvs:
            if npeep[ns+2].opcode = d_lab then
               if npeep[ns+2].operand = operand then
                  if npeep[ns+1].opcode = m_bmi then
                     if npeep[ns+4].opcode = d_lab then
                        if npeep[ns+1].operand = npeep[ns+4].operand then
                           if npeep[ns+3].opcode = m_brl then
                              if Short(ns,npeep[ns+3].operand) then
                                 if Short(ns+1,npeep[ns+3].operand) then begin
                                    operand := npeep[ns+3].operand;
                                    npeep[ns+1].operand := npeep[ns+3].operand;
                                    npeep[ns+1].opcode := m_bpl;
                                    Remove(ns+3);
                                    end; {if}

         m_dec_abs:
            if npeep[ns+1].opcode = m_lda_abs then
               if name^ = npeep[ns+1].name^ then
                  if npeep[ns+2].opcode = m_beq then
                     Remove(ns+1);

         m_lda_abs:
            if npeep[ns+1].opcode = m_clc then begin
               if npeep[ns+2].opcode = m_adc_abs then
                  if operand = npeep[ns+2].operand then
                     if name = npeep[ns+2].name then
                        if not rangeCheck then begin
                           npeep[ns+1].opcode := m_asl_a;
                           Remove(ns+2);
                           end; {if}
               end {if}
            else if npeep[ns+1].opcode = m_dea then begin
               if npeep[ns+2].opcode = m_tax then begin
                  opcode := m_ldx_abs;
                  npeep[ns+1].opcode := m_dex;
                  Remove(ns+2);
                  end; {if}
               end {else if}
            else if npeep[ns+2].opcode = m_sta_abs then begin
               if npeep[ns+1].opcode in [m_ora_dir,m_ora_abs,m_ora_dirX,
                  m_ora_imm,m_ora_longX,m_ora_s] then
                  if operand = npeep[ns+2].operand then
                     if name = npeep[ns+2].name then begin
                        npeep[ns+1].opcode := npeep[ns+1].opcode + $00A0;
                        npeep[ns+2].opcode := m_tsb_abs;
                        Remove(ns);
                        end; {if}
               end {else if}
            else if SignExtension(ns+1) then begin
               npeep[ns+2] := npeep[ns];
               Remove(ns);
               end {else if}
            else if npeep[ns+1].opcode = m_xba then
               if npeep[ns+2].opcode = m_and_imm then
                  if npeep[ns+2].operand = $00FF then begin
                     operand := operand+1;
                     Remove(ns+1);
                     end; {if}
                
         m_lda_dir:
            if npeep[ns+1].opcode = m_clc then begin
               if npeep[ns+2].opcode = m_adc_dir then
                  if operand = npeep[ns+2].operand then
                     if not rangeCheck then begin
                        npeep[ns+1].opcode := m_asl_a;
                        Remove(ns+2);
                        end; {if}
               end
            else if npeep[ns+1].opcode = m_dea then begin
               if npeep[ns+2].opcode = m_tax then begin
                  opcode := m_ldx_dir;
                  npeep[ns+1].opcode := m_dex;
                  Remove(ns+2);
                  end; {if}
               end {else if}
            else if npeep[ns+1].opcode = m_pha then begin
               if longA then begin
                  opcode := m_pei_dir;
                  Remove(ns+1);
                  end {if}
               end {else if}
            else if npeep[ns+2].opcode = m_sta_dir then begin
               if npeep[ns+1].opcode in [m_ora_dir,m_ora_abs,m_ora_dirX,
                  m_ora_imm,m_ora_longX,m_ora_s] then
                  if operand = npeep[ns+2].operand then begin
                     npeep[ns+1].opcode := npeep[ns+1].opcode + $00A0;
                     npeep[ns+2].opcode := m_tsb_dir;
                     Remove(ns);
                     end {if}
               end {else if}
            else if SignExtension(ns+1) then begin
               npeep[ns+2] := npeep[ns];
               Remove(ns);
               end {else if}
            else if npeep[ns+1].opcode = m_xba then
               if npeep[ns+2].opcode = m_and_imm then
                  if npeep[ns+2].operand = $00FF then begin
                     operand := operand+1;
                     Remove(ns+1);
                     end; {if}
                              
         m_pei_dir:
            if npeep[ns+1].opcode = m_pla then begin
               opcode := m_lda_dir;
               Remove(ns+1);
               end; {if}

         m_lda_imm:
            if npeep[ns+1].opcode = m_pha then
               if ASafe(ns+2) then
                  if longA then begin
                     opcode := m_pea;
                     Remove(ns+1);
                     end; {if}

         m_ldx_imm:
            if npeep[ns+1].opcode = m_lda_imm then
               if npeep[ns+2].opcode = m_phx then
                  if npeep[ns+3].opcode = m_pha then begin
                     opcode := m_pea;
                     npeep[ns+1].opcode := m_pea;
                     Remove(ns+2);
                     Remove(ns+2);
                     end; {if}

         m_ldy_imm:
            if npeep[ns+1].opcode = m_sep then
               if npeep[ns+1].operand = 32 then begin
                  didOne := true;
                  tn := npeep[ns];
                  npeep[ns] := npeep[ns+1];
                  npeep[ns+1] := tn;
                  end; {if}

         m_ora_abs:     
            if npeep[ns+1].opcode = m_sta_abs then
               if operand = npeep[ns+1].operand then
                  if name = npeep[ns+1].name then begin
                     opcode := m_tsb_abs;
                     Remove(ns+1);
                     end; {if}

         m_ora_dir:     
            if npeep[ns+1].opcode = m_sta_dir then
               if operand = npeep[ns+1].operand then begin
                  opcode := m_tsb_dir;
                  Remove(ns+1);
                  end; {if}

         m_pea:     
            if npeep[ns+1].opcode = m_pla then begin
               opcode := m_lda_imm;
               Remove(ns+1);
               end; {if}

         m_sta_abs:     
            if npeep[ns+1].opcode = m_lda_abs then
               if operand = npeep[ns+1].operand then
                  if name = npeep[ns+1].name then
                     if not (npeep[ns+2].opcode in
                        [m_bcc,m_bcs,m_beq,m_bmi,m_bne,m_bpl,m_bvs]) then
                        Remove(ns+1);

         m_sta_dir:
            if npeep[ns+1].opcode = m_lda_dir then
               if operand = npeep[ns+1].operand then
                  if not (npeep[ns+2].opcode in
                     [m_bcc,m_bcs,m_beq,m_bmi,m_bne,m_bpl,m_bvs]) then
                     Remove(ns+1);

         m_plb:
            if npeep[ns+1].opcode = m_phb then begin
               Remove(ns);
               Remove(ns);
               end; {if}

         m_plx:
            if npeep[ns+1].opcode = m_pha then begin
               opcode := m_sta_s;
               mode := direct;
               operand := 1;
               Remove(ns+1);
               end; {if}

         m_tax:
            if npeep[ns+1].opcode = m_phx then begin
               Remove(ns+1);
               opcode := m_pha;
               end {if}
            else if npeep[ns+1].opcode = m_txa then begin
               if not (npeep[ns+2].opcode in
                  [m_bcc,m_bcs,m_beq,m_bmi,m_bne,m_bpl,m_bvs]) then begin
                  Remove(ns);
                  Remove(ns);
                  end; {if}
               end {else if}
            else if npeep[ns+1].opcode = m_dey then
               if npeep[ns+2].opcode = m_dey then
                  if npeep[ns+3].opcode = m_lda_indly then
                     if npeep[ns+4].opcode = m_stx_dir then begin
                        npeep[ns] := npeep[ns+4];
                        opcode := m_sta_dir;
                        Remove(ns+4);
                        end; {if}

         m_tya:
            if npeep[ns+1].opcode = m_sta_dir then begin
               npeep[ns+1].opcode := m_sty_dir;
               Remove(ns);
               end {if}
            else if npeep[ns+1].opcode = m_sta_abs then begin
               npeep[ns+1].opcode := m_sty_abs;
               Remove(ns);
               end; {else if}

         m_tyx:
            if npeep[ns+1].opcode = m_phx then begin
               Remove(ns+1);
               opcode := m_phy;
               end; {if}

         m_pha:
            if npeep[ns+1].opcode = m_pla then begin
               Remove(ns);
               Remove(ns);
               end {if}
            else if npeep[ns+1].opcode in [m_ldx_abs,m_ldx_dir] then
               if npeep[ns+2].opcode = m_pla then begin
                  Remove(ns+2);
                  Remove(ns);
                  end; {if}

         m_phy:
            if npeep[ns+1].opcode = m_ply then begin
               Remove(ns);
               Remove(ns);
               end; {if}

         m_rep:
            if npeep[ns+1].opcode = m_sep then
               if npeep[ns].operand = npeep[ns+1].operand then begin
        	  Remove(ns);
        	  Remove(ns);
        	  end; {if}

         otherwise: ;

         end; {case}
1:
  end; {Optimize}

begin {GenNative}
{ writeln('GenNative: ',p_opcode:4, ', mode=', ord(p_mode):1,
   ' operand=', p_operand:1);      {debug}
if npeephole then begin
   if (nnextspot = 1) and not (p_opcode in nleadOpcodes) then begin
      if p_opcode <> d_end then
         if registers then
            CheckRegisters(p_opcode, p_mode, p_operand, p_name, p_flags)
         else
            WriteNative(p_opcode, p_mode, p_operand, p_name, p_flags);
      end {if}
   else if p_opcode in nstopOpcodes then begin
      repeat
         didOne := false;
         i := 1;
         llongA := longA;
         while i < nnextSpot-nMaxPeep do begin
            op := npeep[i].opcode;
            if op = m_sep then begin
               if npeep[i].operand & $20 <> 0 then
                  llongA := false;
               end {if}
            else if op = m_rep then begin
               if npeep[i].operand & $20 <> 0 then
                  llongA := true;
               end; {else}
            Optimize(i,llongA);
            i := i+1;
            end; {while}
      until not didone;
      Purge;
      if p_opcode <> d_end then
         if registers then
            CheckRegisters(p_opcode, p_mode, p_operand, p_name, p_flags)
         else
            WriteNative(p_opcode, p_mode, p_operand, p_name, p_flags);
      end {else if}
   else if nnextSpot = npeepSize then begin
      repeat
         didOne := false;
         i := 1;
         llongA := longA;
         while i < nnextSpot-nMaxPeep do begin
            op := npeep[i].opcode;
            if op = m_sep then begin
               if npeep[i].operand & $20 <> 0 then
               llongA := false;
               end {if}
            else if op = m_rep then begin
               if npeep[i].operand & $20 <> 0 then
               llongA := true;
               end; {else}
            Optimize(i,llongA);
            i := i+1;
            end; {while}
      until not didone;
      done := false;
      repeat
         if nnextSpot = 1 then
            done := true
         else begin
            if npeep[1].opcode in nleadOpcodes then
               done := true
            else begin
               if registers then
                  CheckRegisters(nPeep[1].opcode, nPeep[1].mode,
                     nPeep[1].operand, nPeep[1].name, nPeep[1].flags)
               else
                  WriteNative(nPeep[1].opcode, nPeep[1].mode, nPeep[1].operand,
                     nPeep[1].name,nPeep[1].flags);
               Remove(1);
               end; {else}
            end; {else}
      until done;
      if nnextSpot = nPeepSize then begin
         if registers then
            CheckRegisters(nPeep[1].opcode, nPeep[1].mode, nPeep[1].operand,
               nPeep[1].name, nPeep[1].flags)
         else
            WriteNative(nPeep[1].opcode, nPeep[1].mode, nPeep[1].operand,
               nPeep[1].name, nPeep[1].flags);
         Remove(1);
         end; {if}
      with npeep[nnextSpot] do begin
         opcode := p_opcode;
         mode := p_mode;
         operand := p_operand;
         name := p_name;
         flags := p_flags;
         end; {with}
      nnextSpot := nnextSpot+1;
      if not (npeep[1].opcode in nleadOpcodes) then begin
         if registers then
            CheckRegisters(nPeep[1].opcode, nPeep[1].mode, nPeep[1].operand,
               nPeep[1].name, nPeep[1].flags)
         else
            WriteNative(nPeep[1].opcode, nPeep[1].mode, nPeep[1].operand,
               nPeep[1].name, nPeep[1].flags);
         Remove(1);
         end; {if}
      end {else if}
   else begin
      with npeep[nnextSpot] do begin
         opcode := p_opcode;
         mode := p_mode;
         operand := p_operand;
         name := p_name;
         flags := p_flags;
         end; {with}
      nnextSpot := nnextSpot+1;
      end; {else}
   end {if}
else if p_opcode <> d_end then
   if registers then
      CheckRegisters(p_opcode, p_mode, p_operand, p_name, p_flags)
   else
      WriteNative(p_opcode, p_mode, p_operand, p_name, p_flags);
end; {GenNative}


procedure GenImplied {p_opcode: integer};

{ short form of GenNative - reduces code size                   }
{                                                               }
{ parameters:                                                   }
{       p_code - operation code                                 }

begin {GenImplied}
GenNative(p_opcode, implied, 0, nil, 0);
end; {GenImplied}


procedure GenCall {callNum: integer};

{ short form of jsl to library subroutine - reduces code size   }
{                                                               }
{ parameters:                                                   }
{       callNum - subroutine # to generate a call for           }

var
   sp: pStringPtr;                       {work string}

begin {GenCall}
case callNum of
      1: sp := @'~GET';
      2: sp := @'~PUT';
      3: sp := @'~OPEN';
      4: sp := @'~CLOSE';
      5: sp := @'~READINT';
      6: sp := @'~READREAL';
      7: sp := @'~READCHAR';
      8: sp := @'~WRITECHAR';
      9: sp := @'~WRITEINTEGER';
     10: sp := @'~WRITEREAL';
     11: sp := @'~PNEW';
     12: sp := @'~XJPERROR';
     13: sp := @'~READLN';
     14: sp := @'~WRITELINE';
     15: sp := @'~PAGE';
     16: sp := @'~INTTOSET';
     17: sp := @'~DISPOSE';
     18: sp := @'~LOADDOUBLE';
     19: sp := @'~PUTSP';
     20: sp := @'~PUTB';
     21: sp := @'~PUT2';
     22: sp := @'~PUTC';
     23: sp := @'~SAVEREAL';
     24: sp := @'~SAVESET';
     25: sp := @'~LOADREAL';
     26: sp := @'~WRITELINESO';
     27: sp := @'~WRITELINEEO';
     28: sp := @'~LOADSET';
     29: sp := @'~CNN';
     30: sp := @'~SETEQU';
     31: sp := @'~EQUE';
     32: sp := @'~MUL2';
     33: sp := @'~CHECK';
     34: sp := @'~CHECKPTR';
     35: sp := @'~CLEARMEM';
     36: sp := @'~CNVINTREAL';
     37: sp := @'~CNVREALINT';
     38: sp := @'~SETDIFFERENCE';
     39: sp := @'~SETINTERSECTION';
     40: sp := @'~SETUNION';
     41: sp := @'~DIV2';
     42: sp := @'~SETIN';
     43: sp := @'~MUL2';
     44: sp := @'~SEEK';
     45: sp := @'~WRITESTRING';
     46: sp := @'~PUTBOOLEAN';
     47: sp := @'~PRODOS';
     48: sp := @'~EOF';
     49: sp := @'~EOLN';
     50: sp := @'~ADDE';
     51: sp := @'~DIVE';
     52: sp := @'~MULE';
     53: sp := @'~SUBE';
     54: sp := @'~SQRE';
     55: sp := @'~SQTE';
     58: sp := @'~READCHARINPUT';
     59: sp := @'~READINTINPUT';
     60: sp := @'~READLNINPUT';
     61: sp := @'~READREALINPUT';
     62: sp := @'~WRITEREALOUTPUT';
     63: sp := @'~SINE';
     64: sp := @'~COSE';
     65: sp := @'~ATNE';
     66: sp := @'~LOGE';
     67: sp := @'~EXPE';
     68: sp := @'~ROUND';
     69: sp := @'~EQUSTRING';
     70: sp := @'~GRTE';
     71: sp := @'~GEQE';
     72: sp := @'~GRTSTRING';
     73: sp := @'~GEQSTRING';
     74: sp := @'~SETINCLUSION';
     75: sp := @'~SETLINENUMBER';
     76: sp := @'~SETNAME';
     77: sp := @'~RESETNAME';
     78: sp := @'~SETSIZE';
     79: sp := @'~READSTRINGINPUT';
     80: sp := @'~MOVE';
     81: sp := @'~REALRET2';
     82: sp := @'~REALFN';
     83: sp := @'~REALFIX';
     84: sp := @'~DOUBLERET2';
     85: sp := @'~DOUBLEFN';
     86: sp := @'~DOUBLEFIX';
     87: sp := @'~SAVEDOUBLE';
     88: sp := @'~SHIFTLEFT';
     89: sp := @'~SSHIFTRIGHT';
     90: sp := @'~POWER';
     91: sp := @'~HALT';
     92: sp := @'~PSEED';
     93: sp := @'~DELETE';
     94: sp := @'~INSERT';
     95: sp := @'~SHELLID';
     96: sp := @'~READCMDLINE';
     97: sp := @'~STARTGRAPH';
     98: sp := @'~STARTDESK';
     99: sp := @'~ENDGRAPH';
    100: sp := @'~ENDDESK';
    101: sp := @'~ORD4';
    102: sp := @'~CNVES';
    103: sp := @'~CNVIS';
    104: sp := @'~CNVSE';
    105: sp := @'~CNVSI';
    106: sp := @'~CNVSL';
    107: sp := @'~RANDOME';
    108: sp := @'~RANDOMI';
    109: sp := @'~READSTRING';
    110: sp := @'~CONCAT';
    111: sp := @'~COPY';
    112: sp := @'~LENGTH';
    113: sp := @'~POS';
{   114: sp := @'~USER_ID';  }
    115: sp := @'~CNV42';
    116: sp := @'~MOVESTRING';
    117: sp := @'~DISPOSESTRHEAP';
    118: sp := @'~CNVLS';
    120: sp := @'~TANE';
    121: sp := @'~ARCCOSE';
    122: sp := @'~ARCSINE';
    123: sp := @'~ARCTAN2E';
    124: sp := @'~MOD2';
    125: sp := @'~PACK2';
    126: sp := @'~UNPACK2';
    127: sp := @'~MAKESET';
    128: sp := @'~WRITEREALEO';
    129: sp := @'~CHECKSTACK';
    130: sp := @'~SETINA';
    131: sp := @'~NEWOPENREC';
    132: sp := @'~DISPOSEOPENREC';
    133: sp := @'~MUL4';
    134: sp := @'~PDIV4';
    135: sp := @'~PMOD4';
    136: sp := @'~SHL4';
    137: sp := @'~SHR4';
    138: sp := @'~GRTL';
    139: sp := @'~GEQL';
    140: sp := @'~READLONGINPUT';
    141: sp := @'~READLONG';
    142: sp := @'~UMUL2';
    143: sp := @'~PUT4';
    144: sp := @'~WRITELONG';
    145: sp := @'~CNVLE';
    146: sp := @'~CNVL2';
    147: sp := @'~INTCHK';
    148: sp := @'~REDIRECT';
    149: sp := @'~ROUND4';
    150: sp := @'~CNVREALLONG';
    151: sp := @'SYSCHAROUT';
    152: sp := @'SYSCHARERROUT';
    153: sp := @'~WRITESTRINGSO';
    154: sp := @'~WRITESTRINGEO';
    155: sp := @'~WRITELNSTRINGSO';
    156: sp := @'~WRITELNSTRINGEO';
    157: sp := @'~SAVECOMP';
    158: sp := @'~SAVEEXTENDED';
    159: sp := @'~COPYREAL';
    160: sp := @'~COPYDOUBLE';
    161: sp := @'~COPYCOMP';
    162: sp := @'~COPYEXTENDED';
    163: sp := @'~LOADCOMP';
    164: sp := @'~LOADEXTENDED';
    165: sp := @'~UDIV2';
    166: sp := @'~CNVLONGREAL';
    167: sp := @'~MOVE2';
    168: sp := @'~LONGMOVE';
    169: sp := @'~LONGMOVE2';
    170: sp := @'~LSHR4';
    171: sp := @'~ASHR4';
    172: sp := @'~UMUL4';
    173: sp := @'~UDIV4';
    174: sp := @'~UMOD4';
    175: sp := @'~USHIFTRIGHT';
    176: sp := @'~EXTENDEDRET2';
    177: sp := @'~COMPRET2';
    178: sp := @'~COMPFIX';
    179: sp := @'~CHECKLONG';
    180: sp := @'~PNEW4';
    181: sp := @'~MEMBER';
    182: sp := @'~NEWOBJECT';
    183: sp := @'~STRINGPSIZE';
    184: sp := @'~STRINGCSIZE';
    185: sp := @'~EOFSTDIN';
    186: sp := @'~EOLNSTDIN';
   otherwise:      
      Error(cge1);
   end; {case}
GenNative(m_jsl, longabs, 0, sp, 0);
end; {GenCall}


procedure InitFile {keepName: gsosOutStringPtr; keepFlag: integer; partial: boolean};

{ Set up the object file					}
{                                                               }
{ parameters:							}
{    keepName - name of the output file				}
{    keepFlag - keep status:					}
{       0 - don't keep the output				}
{       1 - create a new object module				}
{       2 - a .root already exists				}
{       3 - at least on .letter file exists			}
{    partial - is this a partial compile?			}
{								}
{ Note: Declared as extern in CGI.pas				}


   procedure RootFile;

   { Create and write the initial entry segment                 }

   const
      dispToOpen     =     21;          {disps to glue routines for NDAs}
      dispToClose    =     38;
      dispToAction   =     50;
      dispToInit     =     65;
      dispToCDAOpen  =     9;           {disps to glue routines for CDAs}
      dispToCDAClose =     36;

   var
      i: integer;                       {loop index}
      lab: pStringPtr;			{for holdling names var pointers}
      menuLen: integer;                 {length of the menu name string}


      procedure SetDataBank;

      { set up the data bank register                           }

      begin {SetDataBank}
      CnOut(m_pea);
      RefName(@'~GLOBALS', 0, 2, -8);
      CnOut(m_plb);
      CnOut(m_plb);
      end; {SetDataBank}


   begin {RootFile}
   {open the initial object module}
   fname2.theString.theString := concat(fname1.theString.theString, '.root');
   fname2.theString.size := length(fname2.theString.theString);
   OpenObj(fname2);
   
   {write the header}
   Header(@'~_ROOT', $4000, 0);
   
   {new desk accessory initialization}
   if isNewDeskAcc then begin

      {set up the initial jump table}
      lab := @'~_ROOT';
      menuLen := length(menuLine);
      RefName(lab, menuLen + dispToOpen, 4, 0);
      RefName(lab, menuLen + dispToClose, 4, 0);
      RefName(lab, menuLen + dispToAction, 4, 0);
      RefName(lab, menuLen + dispToInit, 4, 0);
      CnOut2(refreshPeriod);
      CnOut2(eventMask);
      for i := 1 to menuLen do
         CnOut(ord(menuLine[i]));
      CnOut(0);

      {glue code for calling open routine}
      CnOut(m_phb);
      SetDataBank;
      CnOut(m_jsl);
      RefName(openName, 0, 3, 0);
      CnOut(m_plb);
      CnOut(m_sta_s); CnOut(4);
      CnOut(m_txa);
      CnOut(m_sta_s); CnOut(6);
      CnOut(m_rtl);

      {glue code for calling close routine}
      CnOut(m_phb);
      SetDataBank;
      CnOut(m_jsl);
      RefName(closeName, 0, 3, 0);
      CnOut(m_plb);
      CnOut(m_rtl);

      {glue code for calling action routine}
      CnOut(m_phb);
      SetDataBank;
      CnOut(m_pha);
      CnOut(m_phy);
      CnOut(m_phx);
      CnOut(m_jsl);
      RefName(actionName, 0, 3, 0);
      CnOut(m_plb);
      CnOut(m_rtl);

      {glue code for calling init routine}
      CnOut(m_pha);
      CnOut(m_jsl);
      RefName(@'~DAID', 0, 3, 0);
      CnOut(m_phb);
      SetDataBank;
      CnOut(m_pha);
      CnOut(m_jsl);
      RefName(initName, 0, 3, 0);
      CnOut(m_plb);
      CnOut(m_rtl);
      end

   {classic desk accessory initialization}
   else if isClassicDeskAcc then begin

      {write the name}
      menuLen := length(menuLine);
      CnOut(menuLen);
      for i := 1 to menuLen do
         CnOut(ord(menuLine[i]));

      {set up the initial jump table}
      lab := @'~_ROOT';
      RefName(lab, menuLen + dispToCDAOpen, 4, 0);
      RefName(lab, menuLen + dispToCDAClose, 4, 0);

      {glue code for calling open routine}
      CnOut(m_pea);
      CnOut2(1);
      CnOut(m_jsl);
      RefName(@'~DAID', 0, 3, 0);
      CnOut(m_phb);
      SetDataBank;
      CnOut(m_jsl);
      RefName(@'~CDASTART', 0, 3, 0);
      CnOut(m_jsl);
      RefName(openName,0,3,0);
      CnOut(m_jsl);
      RefName(@'~CDASHUTDOWN', 0, 3, 0);
      CnOut(m_plb);
      CnOut(m_rtl);

      {glue code for calling close routine}
      CnOut(m_phb);
      SetDataBank;
      CnOut(m_jsl);
      RefName(closeName, 0, 3, 0);
      CnOut(m_pea);
      CnOut2(0);
      CnOut(m_jsl);
      RefName(@'~DAID', 0, 3, 0);
      CnOut(m_plb);
      CnOut(m_rtl);
      end

   {control panel device initialization}
   else if isCDev then begin
      CnOut(m_pea);
      CnOut2(1);
      CnOut(m_jsl);
      RefName(@'~DAID', 0, 3, 0);
      CnOut(m_phb);
      SetDataBank;
      CnOut(m_pla);
      CnOut(m_sta_s); CnOut(13);
      CnOut(m_pla);
      CnOut(m_sta_s); CnOut(13);
      CnOut(m_jsl);
      RefName(openName,0,3,0);
      CnOut(m_tay);
      CnOut(m_lda_s); CnOut(3);
      CnOut(m_pha);
      CnOut(m_lda_s); CnOut(3);
      CnOut(m_pha);
      CnOut(m_txa);
      CnOut(m_sta_s); CnOut(7);
      CnOut(m_tya);
      CnOut(m_sta_s); CnOut(5);
      CnOut(m_plb);
      CnOut(m_rtl);
      end

   {NBA initialization}
   else if isNBA then begin
      CnOut(m_jsl);
      RefName(@'~NBASTARTUP', 0, 3, 0);
      CnOut(m_phx);
      CnOut(m_phy);
      CnOut(m_jsl);
      RefName(openName,0,3,0);
      CnOut(m_jsl);
      RefName(@'~NBASHUTDOWN', 0, 3, 0);
      CnOut(m_rtl);
      end

   {XCMD initialization}
   else if isXCMD then begin
      CnOut(m_jsl);
      RefName(@'~XCMDSTARTUP', 0, 3, 0);
      CnOut(m_jsl);
      RefName(openName,0,3,0);
      CnOut(m_jsl);
      RefName(@'~XCMDSHUTDOWN', 0, 3, 0);
      CnOut(m_rtl);
      end

   {normal program initialization}
   else begin

      {write the initial JSL}
      CnOut(m_jsl);
      if rtl then
         RefName(@'~_BWSTARTUP4', 0, 3, 0)
      else
         RefName(@'~_BWSTARTUP3', 0, 3, 0);

      {set the data bank register}
      SetDataBank;

      {write JSL to main entry point}
      CnOut(m_jsl);
      RefName(@'~_PASMAIN', 0, 3, 0);

      {return to the shell}
      CnOut(m_lda_imm); CnOut2(0);
      CnOut(m_jml);
      if rtl then 
	 RefName(@'~RTL', 0, 3, 0)
      else
	 RefName(@'~QUIT', 0, 3, 0);
      end;

   {finish the current segment}
   EndSeg;
   end; {RootFile}


   procedure SetStack;

   { Set up a stack frame					}

   begin {SetStack}
   if stackSize <> 0 then begin
      currentSegment := '~_STACK   ';	{write the header}
      Header(@'~_STACK', $4012, 0);
      currentSegment := defaultSegment;
      Out($F1);				{write the DS record to reserve space}
      Out2(stackSize);
      Out2(0);
      EndSeg;				{finish the current segment}
      end; {if}
   end; {SetStack}


begin {InitFile}
fname1 := keepname^;
if partial or (keepFlag = 3) then
   FindSuffix(fname1, nextSuffix)
else begin
   if (keepFlag = 1) and (not doingunit) then begin
       RootFile;
       SetStack;
       CloseObj;
       end; {if}
   DestroySuffixes(fname1);
   nextSuffix := 'a';
   end; {else}
fname2.theString.theString := concat(fname1.theString.theString, '.', nextSuffix);
fname2.theString.size := length(fname2.theString.theString);
OpenObj(fname2);
end; {InitFile}  


procedure InitNative; 

{ set up for a new segment					}

begin {InitNative}
aRegister.condition := regUnknown;	{set up the peephole optimizer}
xRegister.condition := regUnknown;
yRegister.condition := regUnknown;
nnextspot := 1;
nleadOpcodes := [m_asl_a,m_bcs,m_beq,m_bmi,m_bne,m_bpl,m_brl,m_bvs,m_bcc,
   m_dec_abs,m_lda_abs,m_lda_dir,m_lda_imm,m_ldx_imm,m_sta_abs,m_sta_dir,
   m_pha,m_plb,m_plx,m_tax,m_tya,m_tyx,m_phy,m_pei_dir,m_ldy_imm,m_rep,
   m_ora_dir,m_ora_abs,m_and_imm,m_pea];
nstopOpcodes := [d_end,d_pin];

stringSize := 0;			{initialize scalars for a new segment}
pc := 0;
cbufflen := 0;
longA := true;
longI := true;
end; {InitNative}


procedure GenLab {lnum: integer};

{ generate a label                                              }
{                                                               }
{ parameters:                                                   }
{       lnum - label number                                     }

begin {GenLab}
GenNative(d_lab, gnrlabel, lnum, nil, 0);
end; {GenLab}


procedure LabelSearch {lab: integer; len, shift, disp: integer};

{ resolve a label reference                                     }
{                                                               }
{ parameters:                                                   }
{       lab - label number                                      }
{       len - # bytes for the generated code                    }
{       shift - shift factor                                    }
{       disp - disp past the label                              }
{                                                               }
{ Note 1: maxlabel is reserved for use as the start of the      }
{       string space                                            }
{ Note 2: negative length indicates relative branch             }
{ Note 3: zero length indicates 2 byte addr -1                  }

var
   next: labelptr;                      {work pointer}

begin {LabelSearch}
if labeltab[lab].defined and (len < 0) and (shift = 0) and (disp = 0) then begin

   {handle a relative branch to a known disp}
   if len = -1 then
      CnOut(labeltab[lab].ival - long(pc).lsw - cbufflen + len)
   else
      CnOut2(labeltab[lab].ival - long(pc).lsw - cbufflen + len);
   end {if}
else begin
   if lab <> maxlabel then begin

      {handle a normal label reference}
      Purge;                            {empty the constant buffer}
      if len < 0 then begin
         len := -len;                   {generate a RELEXPR}
         Out(238);
         Out(len);
         Out2(len); Out2(0);
         end {if}
      else begin
         if isJSL then                  {generate a standard EXPR}
            Out(243)
         else
            Out(235);
         if len = 0 then
            Out(2)
         else
            Out(len);
         end; {else}
      end; {if}
   Out(135);                            {generate a relative offset from the seg. start}
   if not labeltab[lab].defined then begin
      next := pointer(Malloc(sizeof(labelEntry))); {value unknown: create a reference}
      next^.next := labeltab[lab].chain;
      labeltab[lab].chain := next;
      next^.addr := blkcnt;
      Out2(0);
      Out2(0);
      end {if}
   else {labeltab[lab].defined} begin
      Out2(labeltab[lab].ival);         {value known: write it}
      Out2(labeltab[lab].hval);
      end; {else}
   if len = 0 then begin
      Out(129);                         {subtract 1 from addr}
      Out2(1); Out2(0);
      Out(2);
      len := 2;
      end; {if}
   if disp <> 0 then begin
      Out(129);                         {add in the displacement}
      Out2(disp);
      if disp < 0 then
         Out2(-1)
      else
         Out2(0);
      Out(1);
      end; {if}
   if shift <> 0 then begin
      Out(129);                         {shift the address}
      Out2(-shift); Out2(-1);
      Out(7);
      end; {if}
   if lab <> maxlabel then              {if not a string, end the expression}
      Out(0);
   pc := pc+len;                        {update the pc}
   end; {else}
end; {LabelSearch}


procedure RefName {lab: pStringPtr; disp, len, shift: integer};

{ handle a reference to a named label                           }
{                                                               }
{ parameters:                                                   }
{       lab - label name                                        }
{       disp - displacement past the label                      }
{       len - number of bytes in the reference                  }
{       shift - shift factor                                    }

var
   i: integer;                          {loop var}
   slen: integer;                       {length of string}

begin {RefName}
Purge;                                  {clear any constant bytes}
if isJSL then                           {expression header}
   Out(243)
else
   Out(235);
Out(len);
Out(131);
pc := pc+len;
slen := length(lab^);
Out(slen);
for i := 1 to slen do
   Out(ord(lab^[i]));
if disp <> 0 then begin                 {if there is a disp, add it in}
   Out(129);
   Out2(disp);
   Out2(0);
   Out(1);
   end; {end}
if shift <> 0 then begin                {if there is a shift, add it in}
   Out(129);
   Out2(shift);
   if shift < 0 then
      Out2(-1)
   else
      Out2(0);
   Out(7);
   end; {if}
Out(0);                                 {end of expression}
end; {RefName}

end.

{$append 'Native.asm'}
