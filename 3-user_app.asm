
;定义常量
;每一项重定位段信息占用12字节
USER_REALLOC_TABLE_EACH_ITEM_BYTES EQU 12

;符号表每一项占用12字节
USER_APP_EACH_TABLE_ITEM_BYTES EQU 12

;符号地址表每一项占用8字节
USER_APP_EACH_TABLE_ITEM_ADDR_BYTES equ 8

;栈段由内核分配,并写入选择子到seg_stack_addr;
;seg_stack_len 提示描述符的G位(以4K还是1字节为单位)

;用户程序如果需要调用内核程序提供的API,则需要符号表帮忙,根据字符串匹配来确定对应的段选择子:偏移地址
;符号表分为2块:
;1.符号信息表
;   1.符号信息表内部又由2部分组成: 符号信息,符号字符串表
;   2.遍历符号信息,可匹配字符串以及获取对应的索引,一旦匹配成功则在地址表中写入(偏移,段选择子)
;2.符号地址表,每一项占8个字节: (4字节)偏移地址:(4字节,仅低2字节有效)段选择子
;   根据信息表内的索引, 索引*8 即可获取过程的偏移,段选择子


[bits 32]
section header vstart=0 align=16

    ;程序长度
    app_len dd tail_end     ;0x00

    ;入口点
    entry   dd start        ;0x04
            dd section.code.start   ;0x08

    ;重定位表项数
    ;0x0c
    realloc_table_len dd  (table_end - table_begin) / USER_REALLOC_TABLE_EACH_ITEM_BYTES

    ;重定位表
    ;被加载后,所有段基址都会被替换成段选择子
    table_begin:
        ;头部段
        seg_header_len dd header_end-1 ;段界限, 0x10
        seg_header_addr dd section.header.start ;段基址, 0x14
        seg_header_attr dd 0x00409200           ;段属性,0x18

        ;代码段
        seg_code_len dd code_end-1  ;段界限,0x1c
        seg_code_addr dd    section.code.start  ;段基址,0x20
        seg_code_attr   dd  0x00409800      ;段属性,0x24    


        ;数据段
        seg_data_len    dd data_end-1   ;段界限,0x28
        seg_data_addr   dd  section.data.start  ;段基址,0x2c
        seg_data_attr   dd 0x00409200       ;段属性,0x30

    table_end:

    ;栈段由内核程序帮忙分配
    ;分配完后由内核程序写入
    ;用户程序在固定位置有占位即可
    ;内核将用最大界限值:0xfffff - 1(这里的数字), 来计算分配多少字节
    seg_stack_len   dd  1   ; 0x34 , 以4K为单位, 这里的1相当于4096字节,与界限相呼应
    seg_stack_addr  dd  0   ; 0x38, 由内核写入栈段选择子

    ;0x3c
    ;符号信息表长度
    symbol_table_len dd (symbol_table_string_start-symbol_table_begin) / USER_APP_EACH_TABLE_ITEM_BYTES

    ;0x40
    ;符号信息表起始位置
    symbol_table_info_start dd symbol_table_begin   

    ;0x44
    ;符号地址表起始位置
    symbol_table_addr_start dd symbol_table_addr_begin

    ;用户程序符号信息表
    symbol_table_begin:
        print_info:  
                    dd (exit - print ) ;字符串长度,用于比较
                    dd print    ;字符串的偏移地址
                    dd 0        ;对应地址表的索引

        exit_info:
					dd (symbol_table_string_end - exit)
                    dd exit     ;字符串偏移地址
                    dd 1        ;索引

        symbol_table_string_start:
            print db 'print'
            exit db 'exit'
        symbol_table_string_end:
    symbol_table_end:
    
    ;用户程序符号地址表
    ;times N db 0 占位
    ;每个地址:(低4字节)偏移,(高4字节)段选择子. 段选择子只有低2字节有效
    ;原本可以把段选择子使用2字节,选择4字节只是为了计算索引方便
    ;匹配成功后,会把 print , exit 的(偏移地址,段选择子)放入此表内
    ;根据print,exit对应的索引,放入指定位置
    ;由于每个地址占8个字节,根据: 索引*8 即可得到其地址
    ; 乘以8 , 相当于 左移3位
    ;例如 exit 的索引是1. 
    ;            1. mov eax, 1 ; 索引
    ;            2. shl eax, 3; 乘8
    ;            就可以得到 exit 的偏移和段选择子
    symbol_table_addr_begin:
        times  ((symbol_table_string_start-symbol_table_begin)/USER_APP_EACH_TABLE_ITEM_BYTES)*USER_APP_EACH_TABLE_ITEM_ADDR_BYTES db 0
    symbol_table_addr_end:

header_end:


section code vstart=0 align=16

    start:
    ;用户程序开始执行
    ;从内核跳转过来, es段指向头部

    ;切换栈段
    mov eax,[es:seg_stack_addr]
    mov ss,eax
    xor esp,esp

    ;切换数据段
    mov eax,[es:seg_data_addr]
    mov ds,eax

    ;显示用户程序自己的消息
    ;print 偏移地址,段选择子 在 符号地址表:0
    push dword (user_msg_end - user_msg)
    push ds
    push dword user_msg
    call far [es:symbol_table_addr_begin + 0]

    ;跳转 exit,将回到core中
    ;exit的索引为1, 1 * 8 为其偏移位置
    jmp far [es:symbol_table_addr_begin + 8]
    


code_end:

section data vstart=0 align=16
    user_msg db 'user is running~~'
    user_msg_end:
data_end:

section tail 
tail_end:
