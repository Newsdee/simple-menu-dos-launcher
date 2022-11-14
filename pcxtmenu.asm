;-------------------
;TINY MENU FOR PC XT
;-------------------

;This will use very little RAM to avoid issues even without EMS on 8088-86
;It was also fun trying to make a whole program in assembly and making it 
;look like C.

;This code is structured like this:
;	-Assembly parameters
;	-Main program (arranged in a c like style for better reading)
;	-Functions used in main (arranged in a c like style for better reading)
;	-Variables and arrays

; github: https://github.com/jsmolina/simple-menu-dos-launcher

;######################################################

.model tiny
.code
org     100h
;1.561  

start:
main    proc
	call Set_Up
	call clear_screen
	call draw_menu
	call count_programs

	_main_loop:
		;if (input)
		cmp key_input,0
		jng _no_input
			call update_list
			call get_image
			mov key_input,0
			call clear_kb
		_no_input:
		
		;Wait for key and read
		;sti;enable interrupts
		xor ax,ax
		int 16h
		mov key_input,ax ;key_input = getch();
		;cli;disable interrupts
		
		;this is a switch case: switch(key_input)
		;case ESC
		cmp key_input,011Bh
		jnz _end_input_ESC
			jmp _exit
		_end_input_ESC:
		
		;case KEY_DOWN
		cmp key_input,5000h
		jnz _end_input_KEY_DOWN
			call menu_down
			jmp _main_loop
		_end_input_KEY_DOWN:
		
		;case KEY_UP
		cmp key_input,4800h
		jnz _end_input_KEY_UP
			call menu_up
			jmp _main_loop
		_end_input_KEY_UP:
		
		;case ENTER
		cmp key_input,1C0Dh
		jnz _main_loop
			call Point_ES_VRAM
			;delete box
			mov di,(22*160)+6
			mov ax,0
			mov cx,56
			rep stosw
			;print "running" at xy 3,22 color 0x0F
			mov	ah,0Fh;text color
			mov di,(22*160)+6
			mov si,offset message0
			mov cx,9
			call print
			;print "executable" at xy 13,22 color 0x0F
			mov di,(22*160)+24
			mov si,offset exec1 +1
			mov	cx,16
			call print
			
			call wait_1s
			call clear_screen
			
			;run program
			mov es,cs:[save_ES]
			;free ram
			mov bx,offset pspblk+0Fh
			mov sp,offset start
			mov cl,4
			shr bx,cl		;bx = size of program/16	
			mov ah,4ah
			int 21h
			
			jnc _continue
			jmp _exit
			_continue:
			
			;change dir
			mov dx,offset path1	;ASCIIZ path name
			mov ah,3Bh
			int 21h
			;run
			;sti;enable interrupts
			;lea     dx,exec1
			;lea     bx,Psp
			;mov     ax,4b00h
			;int     21h
			
			;lds     si,offset exec1
			mov si,offset exec1
			int 2Eh
			cli
			mov es,CS:[save_ES]
			mov ds,CS:[save_DS]
			sti
			
			;;mov cs,ds
			;cli;disable interrupts
			;Return from program
			call Point_ES_VRAM
			jc	_error		;if there was an error running the program
			call wait_1s
			call clear_screen
			jmp _no_error
			_error:
				call clear_screen
				;printf("File not found");
				mov di,(11*160) + 60
				mov si,offset file_error
				mov	ah,Color_S
				mov cx,16
				call print
				call wait_1s
			_no_error:
			
			;return to menu folder
			mov dx,offset start_dir_path
			mov ah,3Bh
			int 21h
			
			mov key_input,1
			call draw_menu
			call count_programs
		_end_input_ENTER:

		jmp _main_loop
		
	_exit:
	;sti;enable interrupts
	call clear_screen
	mov	ax,4c00h
	int	21h
main    endp



;saved some bytes
;#########################
print proc near
	_loop_print:	
		lodsb
		stosw
		loop _loop_print
	ret
print endp



;clear the screen by setting text mode
;#########################
clear_screen proc near
	mov ax, 0003h;text mode 80x25 16 colours
	int 10h
	ret
clear_screen endp


;clear keyboard buffer
;#########################
clear_kb proc near
	mov ax,0C00h
	int 21h
	ret
clear_kb endp


;Reduce snow by waiting to horizontal and vertical retraces
;#########################
Wait_Retraces proc
	mov dx,3DAh
	_WDN:						;wait until we're out of some random retrace we may have started in}
	in   al,dx					;grab status bits}
	test al,1					;are we in some random horizontal sync cycle?}
	jnz  _WDN						;if so, keep waiting}
	_WDR:						;wait until we're in either vert or horiz retrace}
	in   al,dx					;grab status bits}
	shr  al,1					;shift bit into carry -- were we in retrace?}
	jnc  _WDR  
	ret
Wait_Retraces endp



;VRAM at ES:DI
;#########################
Point_ES_VRAM proc near
	mov ax,TILE_MAP
	mov es,ax
	ret
Point_ES_VRAM endp


;Wait 1s
;#########################
wait_1s proc near
	mov clock_ticks,0
	mov ah,1
	xor cx,cx
	xor dx,dx
	int 1Ah						;Reset clock
	
	_wait:
		xor ah,ah
		int 1Ah					;Read clock
		cmp clock_ticks,15
		jg _stop
		mov clock_ticks,dl		;dx (clock ticks) to variable
		loop _wait
	_stop:
	ret
wait_1s	endp


;init
;#########################
Set_Up proc
	mov CS:[save_DS],ds
	mov CS:[save_ES],es
	call Point_ES_VRAM
	;setup exe parameters
    ;mov cmdseg,cs
    ;mov FCB1seg,cs
    ;mov FCB2seg,cs
	
	;getcwd(start_dir_path,32);
	mov ah,19h						;get drive
	int 21h
	
	add al,65						;al = drive = A B C... (0 1 2 + 64)
	mov si,offset start_dir_path 
	mov ds:[si],al					;store 'A B C..' at the start of path
	add si,3						;skip C:\-----   
	mov ah,47h
	xor dl,dl						;drive number (0 = default, 1 = A:)
	int 21h
	
	ret
Set_Up endp


;Draw ascii graphics (MENU)
;#########################
draw_menu proc near
	mov map_offset,0
	xor di,di		;ES:DI = VRAM
	xor bx,bx
	;copy data from MAP_RLE to VRAM
	_loop:
		mov cl,byte ptr MAP_RLE[bx  ]
		mov	ax,word ptr MAP_RLE[bx+1]
		_loop0:
			mov	word ptr es:[di],ax
			add di,2
			inc map_offset
			dec cl
			jnz _loop0
			
		add bx,3
		cmp map_offset,80*25
		jng _loop

	;Print title
	mov di,(29*2)+2
	mov si,offset mtitle 
	mov	ah,Color_S
	mov cx,20
	call print    
		
	mov di,(22*160)+34
	mov si,offset info
	mov	ah,0Fh
	mov cx,40
	call print
	ret
draw_menu	endp


;read ascii image from folder
;############################
get_image proc near
	mov dx,offset path1	;ASCIIZ path name
	mov ah,3Bh
	int 21h
	
	mov di,(3*160) + 84			;ES:DI = VRAM
	mov read_lines,16
	mov ax,3D00h						;open file, read only
	mov dx,offset THUMB_FILENAME		;filename to open
	int 21h
	mov file_handle,ax
	;if handle == 0x02, file not found				
	cmp file_handle,2					
	jz _no_file
		;else read file
		_loop_img_line:
			;this reads 64 bytes and stores them in read_buffer
			mov ah,3Fh
			mov cx,64
			mov bx,file_handle
			mov dx,offset read_buffer
			int 21h
			
			;This moves 64 bytes from read_buffer (ds:si) to vram E(S:DI)
			mov si,offset read_buffer
			mov cx,32
			call Wait_Retraces
			_loop_transfer:
				lodsw			;ds:[si] => ax, increment si
				stosw			;ax => es:[di], increment di
				loop _loop_transfer
			
			;Jump to next line in video ram
			add di,96
			dec read_lines
			jnz _loop_img_line
		
		;Close file
		mov ah,3Eh					
		mov bx,file_handle				
		int 21h
		jmp _end_get_image
		
	_no_file:
		mov ax,0
		_loop_delete:
			mov cx,32
			call Wait_Retraces
			rep stosw
			add di,96
			dec read_lines
			jnz _loop_delete
		;print message at image position
		mov di,(11*160) + 98
		mov si,offset file_error
		mov	ah,Color_S
		mov cx,14
		call print
	
	_end_get_image:
	mov dx,offset start_dir_path
	mov ah,3Bh
	int 21h
	ret
get_image endp


;Read and update list from file
;############################
update_list proc near

	xor cx,cx	;a bug?
	mov read_lines,0
	mov ax,3D00h					;open file, Read only
	mov dx,offset LIST_FILE			;filename to open
	int 21h
	mov file_handle,ax
	
	;We now know there is a list.txt, read file
	mov di,(3*160)+8			;ES:DI = VRAM
	
	
	;Seek list.txt 
	mov ax,menu_scroll
	inc ax
	mov bx,LIST_LINE_LENGTH
	mul bx						;ax = scroll*line_length
	mov dx,ax					;File position
	mov ax,4201h				;Move pointer from current location
	mov bx,file_handle
	int 21h	
	
	;Write 16 names
	_loop_read_list:
		;this reads 110 bytes (one line) and stores them in read_buffer
		mov ah,3Fh
		mov cx,110
		mov bx,file_handle
		mov dx,offset read_buffer
		int 21h
		
		;If line != 110, goto end of function
		cmp ax,110				
		jnz _end_read_list

		;Check selected item
		mov	ah,Color_N			;Color not selected
		
		;If item selected
		mov cx,menu_selected
		cmp read_lines,cx
		jnz not_selected 		
			mov si,offset read_buffer
			;Store path
			xor bx,bx
			mov cx,16
			_loopA:
				lodsw			;ds:[si] => ax, increment si
				mov word ptr path1[bx],ax
				add bx,2
				loop _loopA
			;store exe
			inc si				;skip tab
			xor bx,bx
			mov cx,8
			_loopB:
				lodsw			;ds:[si] => ax, increment si
				mov word ptr exec1[bx+1],ax
				add bx,2
				loop _loopB
			mov	ah,Color_S		;Color selected
		not_selected:
		;if item not selected, write names to VRAM
		mov si,offset read_buffer+76
		;This moves 16 bytes from buffer (ds:si) to vram (ES:DI)
		call Wait_Retraces
		mov cx,32
		call print
		
		;Jump to next line in video ram
		add di,128-32
		inc read_lines
		cmp read_lines,16
		jnz _loop_read_list

	_end_read_list:
	;Close file
	mov ah,3Eh					
	mov bx,file_handle				
	int 21h
	ret
;>
update_list endp



;Read LIST.TXT and count lines
;#############################
count_programs proc near
	mov ax,3D00h				;open file, Read only
	mov dx,offset LIST_FILE		;filename to open
	int 21h
	mov file_handle,ax
	mov programs,0
	cmp ax,02h					;if ax == 2, no list found				
	jz _no_list_file
		_loop_read:
			;this reads 110 bytes (one line) and stores them in buffer
			mov ah,3Fh
			mov cx,110
			mov bx,file_handle
			mov dx,offset read_buffer
			int 21h
			
			cmp ax,110			;If line != 110, end of file
			jnz _end_read
			inc programs		;count lines
			jmp _loop_read
		
		_end_read:
		;Close file
		mov ah,3Eh					
		mov bx,file_handle				
		int 21h
		jmp _end_count
		
	_no_list_file:
		push es
		call Point_ES_VRAM
		;print message at list position
		mov di,(3*160)+8
		mov si,offset file_error
		mov	ah,Color_S
		mov cx,14
		call print
		
		pop es
		call wait_1s
		call clear_screen
		jmp _exit
	_end_count:
	sub programs,2
	ret
count_programs endp


;MOVE UP
;#############################
menu_up proc near
	;if(menu_selected == 0)
	cmp menu_selected,0
	jnz _sel_not_0
		;if(menu_scroll > 0)
		cmp menu_scroll,0
		jng _is_not_greater		
			dec menu_scroll		;menu_scroll--;
		_is_not_greater:
			jmp _main_loop
		;else
		_sel_not_0: 			
			dec menu_selected	;menu_selected--;
	ret
menu_up endp



;MOVE DOWN
;#############################
menu_down proc near
	;if(menu_selected == 15)
	cmp menu_selected,15
	jnz _sel_not_15
		mov ax,menu_scroll
		add ax,15				;menu_scroll + 15
		;if (menu_scroll + 15 < programs-1)
		cmp ax,programs
		jnb _is_not_below		
			inc menu_scroll			;menu_scroll++;
		_is_not_below:
			jmp _main_loop
		;else
		_sel_not_15:
			inc menu_selected		;menu_selected++;
	ret
menu_down endp




;########################
;--VARIABLES AND ARRAYS--
;########################

key_input 				dw 1
clock_ticks				db 0
save_DS					dw 0
save_ES					dw 0
save_SS					dw 0
;Menu & file
programs				dw 0
menu_scroll 			dw 0
menu_selected 			dw 0
start_dir_path   		db "_:\ ",0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0


;ExecBlk Struc
;Program_Commands 		dw 00h,0dh	; no commands
;Psp     				dw 0	; create and allocate a duplicate of current environment for child.
;Cmdline					dw offset Program_Commands
;CmdSeg  				dw ?	; CS or DS in tiny model
;FCB1    				dw 5ch
;FCB1seg 				dw ?	; CS or DS in tiny model
;FCB2    				dw 6ch
;FCB2seg 				dw ?	; CS or DS in tiny model



LIST_LINE_LENGTH		dw 110	;Line length of list.txt
file_handle				dw 0
read_buffer				db 110 dup (0) ;
read_lines				dw 16

;Read list variables
LIST_FILE 				db 'LIST.TXT',0
path1					db 33 dup (0) 
;exec1   				db 17 dup (0) 
exec1					db 11h,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0Dh

;Read Thumbnail variables
THUMB_FILENAME			db 'menu_img.bin',0

;INFO
file_error				db 'FILE NOT FOUND'
mtitle					db 'LOADER MENU FOR PCXT'
info					db 'MOVE = cursors, ESC = exit, ENTER = run '
message0				db 'Running: '

;MAP
map_offset				dw 0
ifdef MDA
Color_S					db 070h 
Color_N					db 010h
TILE_MAP				dw 0B000h
else
Color_S					db 3Fh
Color_N					db 1Fh
TILE_MAP				dw 0B800h
endif

;Character map "compressed" in RLE format
MAP_RLE:
	db 002h,000h,000h,001h,0B0h,008h,001h,0DBh,008h,002h,0DBh,007h,044h,0DBh,00Fh,002h
	db 0DBh,007h,001h,0DBh,008h,001h,0B0h,008h,055h,000h,000h,001h,0DBh,01Fh,001h,0DFh
	db 01Fh,002h,0DFh,01Eh,002h,0DFh,01Ah,002h,0DFh,013h,002h,0DFh,019h,017h,0DFh,018h
	db 001h,0DBh,008h,02Eh,000h,000h,001h,0DBh,00Eh,020h,000h,01Fh,001h,0DBh,008h,02Eh
	db 000h,000h,001h,0DBh,01Ah,020h,000h,01Fh,001h,0DBh,008h,02Eh,000h,000h,001h,0DBh
	db 003h,020h,000h,01Fh,001h,0DBh,009h,02Eh,000h,000h,001h,0DBh,009h,020h,000h,01Fh
	db 001h,0DBh,003h,02Eh,000h,000h,001h,0DBh,008h,020h,000h,01Fh,001h,0DBh,00Ah,02Eh
	db 000h,000h,001h,0DBh,008h,020h,000h,01Fh,001h,0DBh,00Eh,02Eh,000h,000h,001h,0DBh
	db 008h,020h,000h,01Fh,001h,0DBh,00Eh,02Eh,000h,000h,001h,0DBh,008h,020h,000h,01Fh
	db 001h,0DBh,00Ah,02Eh,000h,000h,001h,0DBh,008h,020h,000h,01Fh,001h,0DBh,003h,02Eh
	db 000h,000h,001h,0DBh,008h,020h,000h,01Fh,001h,0DBh,009h,02Eh,000h,000h,001h,0DBh
	db 008h,020h,000h,01Fh,001h,0DBh,008h,02Eh,000h,000h,001h,0DBh,008h,020h,000h,01Fh
	db 001h,0DBh,008h,02Eh,000h,000h,001h,0DBh,008h,020h,000h,01Fh,001h,0DBh,009h,02Eh
	db 000h,000h,001h,0DBh,008h,020h,000h,01Fh,001h,0DBh,003h,02Eh,000h,000h,001h,0DBh
	db 008h,020h,000h,01Fh,001h,0DBh,00Ah,02Eh,000h,000h,001h,0DBh,009h,020h,000h,01Fh
	db 001h,0DBh,00Eh,02Eh,000h,000h,001h,0DBh,003h,001h,0DCh,013h,002h,0DCh,019h,014h
	db 0DCh,018h,002h,0DCh,019h,002h,0DCh,013h,002h,0DCh,01Ah,002h,0DCh,01Eh,001h,0DCh
	db 01Fh,001h,0DBh,00Fh,07Ch,000h,000h,001h,0DFh,078h,04Ch,0DFh,008h,001h,0DFh,078h
	db 002h,000h,000h,001h,0DBh,00Fh,04Ch,000h,00Fh,001h,0DBh,00Fh,002h,000h,000h,001h
	db 0DBh,00Fh,04Ch,000h,00Fh,001h,0DBh,00Fh,002h,000h,000h,001h,0DCh,078h,04Ch,0DCh
	db 008h,001h,0DCh,078h,001h,000h,000h

pspblk  label   byte
end     main
 