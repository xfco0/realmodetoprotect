;用户中断程序
;默认加载器为之前的mbr_loader.asm, 本程序还是被默认加载到0x10000, 扇区号100

;重写 int 9 中断程序
;原 int 9 中断用于接受键盘字符并产生对应的acsii码,存入键盘缓冲区
;新的int 9 中断程序在 user_code_interrupt 段中
;程序使用了bios提供的0x10中断的子程序0xe(显示字符) , 0x16中断的子程序0x00(从键盘缓冲区获取一个字符)
;9号中断和0x16号中断是一对, 9号往键盘缓冲区里存放字符, 0x16获取字符
;下面的程序相当于在9号中断拦了一下

;--------------------中断过程----------------------
;中断码在中断向量表中,中断向量表从0000:0000 ~ 0000:3ff 共1024个字节
;一个中断码对应一个表项(入口), 一个表项占用4个字节, 低地址 偏移 , 高地址 段地址, 最多可以有256个中断
;简单来说内存布局: 偏移地址,段地址
;中断码1的入口地址存放在 : 偏移地址:1 * 4 , 段地址: 1*4 +2
;中断码N的入口地址 : 偏移地址 N * 4 , 段地址 N*4 + 2

;中断过程, 比如中断码N发生中断
;1.pushf        标志寄存器入栈
;2.TF=0,IF=0    TF是单步中断(1是执行单步中断,0是否定),IF是屏蔽中断(0是屏蔽中断,1是接受中断,因为当前已经中断)
;3.push cs , push ip
;4.根据中断码N,跳转到对应的入口地址, 相当于 ip=N*4, cs=N*4+2

;中断返回:
;中断程序执行完后需要返回到原程序中, 使用 : iret (interrupt return)
;iret执行的伪指令是: pop ip, pop cs, popf (弹出标志寄存器)

;新的int 9中由于接管了原int 9, 但只是把字符拿出来看看, 具体工作还要原int 9去做
;因此新int 9还需要调用原int 9, 即需要把原int 9的地址保存起来
;由于新int 9已经是一个中断程序 ,  9 *4 , 9*4+2 的地址已经被替换成自己的了
;无法再去int 9 调用原中断,因此需要模拟 int 中断调用
;模拟顺序 : pushf , 把TF IF置0 , push cs ,push ip 
;把这些步骤简化 : pushf , tf if =0 , call far [原段地址:原偏移]
;------------------------------------------

;此程序被加载到的逻辑段地址
USER_APP_LOADED_SECTION_ADDR EQU 0x1000

;用户头
;具体注释在user_app.asm 中已经写了,这边省略
section user_header vstart=0 align=16
    user_app_len dd  pro_len    ;程序字节数 0x00
    
    ;入口
    user_app_entry dw start     ;偏移地址   0x04
                   dd section.user_code.start   ;文件段地址 0x06
    
    ;重定位表
    realloc_table_start:
            s_user_code dd section.user_code.start  ;0x0a
            s_user_data dd section.user_data.start  ;0x0e
            s_user_stack dd section.user_stack.start    ;0x12
            s_user_header dd section.user_header.start  ;0x16

            ;中断程序在此代码段中
            s_user_code_interrupt dd section.user_code_interrupt.start  ;0x1a
    realloc_table_end:

    ;重定位表长度
    realloc_table_len dw (realloc_table_end - realloc_table_start)/4 ;0x1e

    ;保存mbr栈,用于返回
    mbr_stack dw 0,0        ;0x20,0x22

user_header_end:


;代码段
section user_code vstart=0 align=16

    ;进入后, ds 指向当前的头部 0x1000:0000 
    ;需要修改ss,ds,es.
    start:
        ;修改成自己的栈
        mov ax, [ds:s_user_stack]
        mov ss,ax
        mov sp,user_stack_top

        ;es指向自己的头部
        mov ax,[ds:s_user_header]
        mov es,ax

        ;ds指向自己的数据段
        mov ax,[ds:s_user_data]
        mov ds,ax

        ;================================
        ;安装新的int 9 中断程序
        ;int 9 替换为user_code_interrupt段中的程序
        
        ;屏蔽中断 ,以防在替换中断向量表的时候有中断
        cli
        mov bx,[es:s_user_code_interrupt]   ; 中断程序的段地址
        push es

        mov ax,0 
        mov es,ax               ;es段指向0 .  中断向量表在0x0000:0x0000 ~ 0x03ff

        ;保存原int 9的段和偏移, 在新int 9中还需要调用原int 9
        push word [es:9*4]     
        pop word [ds:int9_addr]         ;保存偏移地址
        push word [es:9*4 + 2]
        pop word [ds:int9_addr + 2]     ;保存段地址

        ;把原int 9的入口替换成自己的
        mov word [es:9*4], int_start         ;替换偏移
        mov word [es:9*4+2], bx              ;替换段地址

        pop es
        sti

        ;================================

        ;show_msg使用中断号来显示字符
        push ds
        push welcome_msg
        call show_msg
        add sp,4

        ;下面使用0x16号中断的0x00号子程序从键盘缓冲区中获取一个字符
        .recv_keys:
            mov ah,0x00         ;参数
            int 0x16            ;使用16号中断, 参数ah:0x00
            cmp ah,0x39           ;如果是空格键0x39则退出
            jz .user_code_exit

            mov ah,0x0e         ;参数
            mov bl,0x07         ;字符属性
            int 0x10            ;参数al是从0x16接受回来的acsii
            jmp .recv_keys


    .user_code_exit:
        ;还原int 9中断入口
        cli
        push es
        mov ax,0
        mov es,ax

        push word [ds:int9_addr]
        pop word [es:9*4]           ;还原偏移

        push word [ds:int9_addr]
        pop word [es:9*4 + 2]       ;还原段地址
        
        pop es
        sti


        mov ax,[es:mbr_stack]   ;偏移
        mov bx,[es:mbr_stack + 2] ;段地址
        mov ss,bx
        mov sp,ax
        retf


;使用bios中断[中断号为0x10]来显示信息字符
;0x10中断号的0x0e 功能用于显示 :
    ;ah指定功能号:0x0e , al:要显示的字符,bl:字符属性
;参数: 偏移, 段地址
show_msg:
    push bp
    mov bp,sp
    push bx
    push ds
    push ax
    push si

    
    mov si,[bp + 6] ;段地址
    mov ds,si
    mov si,[bp + 4] ;偏移

    mov ah,0x0e     ;指定功能号0x0e 用于显示字符
    mov bl,0x07     ;字符属性
    .show_msg_loop:
        mov al,[ds:si]
        cmp al,0
        jz .show_msg_done

        int 0x10        ;调用0x10中断
        inc si
        jmp .show_msg_loop


    .show_msg_done:
    pop si
    pop ax
    pop ds
    pop bx
    mov sp,bp
    pop bp
    ret



user_code_end:

;数据段
section user_data vstart=0 align=16
    welcome_msg db 'welcome',0

    ;存放原int9的偏移,段地址
    int9_addr dw 0,0    ; 偏移 , 段地址

user_data_end:

;新的int 9 中断代码段
section user_code_interrupt vstart=0 align=16
    ;中断入口
    int_start:
    push es
    push ax
    push bx
    push cx

    ;新的int 9 中断从端口0x60中读取一个字符
    ;如果是esc键,则替换屏幕颜色. esc的扫描码是0x1

    ;从端口读取字符
    in al,0x60
    mov bl,al

    ;调用原int 9去处理, 此时已经在中断中,因此模拟 int 9的调用过程
    ;pushf , tf if =0 , call far 
    pushf

    ;由于在中断的时候, tf,if 已经设置成0了, 因此这步可以省略
    ;把tf,if =0, tf,if在第9和第8位
    ;修改标志寄存器
    ;pushf
    ;pop ax
    ;and ah,1111_1100b
    ;push ax
    ;popf

    ;检查es是否还指向自己的头部段, 需要通过es:s_user_data 获取自己的数据段, 原int 9的地址放在这里
    mov ax,es
    cmp ax,USER_APP_LOADED_SECTION_ADDR
    je .get_user_data
    mov ax,USER_APP_LOADED_SECTION_ADDR
    mov es,ax

    .get_user_data:
        mov ax,[es:s_user_data]
        mov es,ax               ; es 指向自己的数据段

    ;调用原int 9
    call far [es:int9_addr]

    ;是否是esc键
    cmp bl,0x01
    jne .int_done

    mov ax,0xb800
    mov es,ax       ;指向显存
    mov bx,1
    mov cx,2000
    ;改变2000个字符属性
    .change_color:
        inc byte [es:bx]
        add bx,2
        loop .change_color


    
    .int_done:
    pop cx
    pop bx
    pop ax
    pop es

    iret
user_code_interrupt_end:

;栈段
section user_stack vstart=0 align=16
    resb 256
user_stack_top:

section user_end align=16
pro_len:
