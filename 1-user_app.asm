;当前是用户程序
;建立一个头部
;头部内的各种信息都是加载器需要的
;align=16 此段以16字节对齐, vstart=0 段内的偏移地址以0开始, 不写vstart比如最后一段,则段内标号以文件首开始算
;SECTION 用于把各自的数据分开便于代码管理. 如果你喜欢把数据,栈和用户指令混在一起也OK,只要你自己能分清


;头部, 用来给加载器足够的信息 来加载此程序
SECTION user_header align=16 vstart=0
    ;当前程序的字节数, 用于加载器来识别需要读取几个扇区
    ;dd 4个字节,  用户程序可能会超过2^16个字节

    user_app_len dd pro_end         ;0x0 对应user_header的偏移

    ;程序入口, 以便加载器完成后,jmp到此程序
    ;start是偏移地址
    ;section.user_code.start 获取段地址, 用法:seciton.某个段.start
    ;段地址使用dd 是因为 此段地址是文件中的汇编地址, 并非内存中的
    ;比如当前程序非常长,假设此代码段的位置超出65536字节, dw 就无法保存了
    user_app_entry dw start         ;0x04
                   dd  section.user_code.start  ;0x06

    
    ;重定位表
    ;由于这些段地址都是文件内的段地址,当加载器读取到内存后,需要重新计算每个段在内存中的位置
    ;这样才能正确访问到每个段的具体地址
    ;因此需要先给出一张表来写入当前文件中的段地址
    ;由于user_end 这个段在程序中不需要访问,用不到,因此不需要去重定位
    ;再次强调, 重定位的目的是为了在程序运行中能访问这些段
    realloc_table_start:
        s_user_code dd section.user_code.start    ;0x0a
        s_user_code_2 dd section.user_code_2.start ;0x0e
        s_user_data dd section.user_data.start      ;0x12
        s_user_stack dd section.user_stack.start    ;0x16
        s_user_header dd section.user_header.start  ;0x1a
    realloc_table_end:

    ;重定位表项数量
    ;每个重定位的段占用4个字节
    realloc_table_len dw (realloc_table_end - realloc_table_start ) / 4 ;0x1e

    ;保存加载器的stack , 偏移(sp) : 段地址(ss)
    mbr_stack dw 0,0                                ;0x20,0x22

user_header_end:


;代码段
SECTION user_code align=16 vstart=0

    ;入口
    start:
    ;当跳转进来的时候, ds 指向 0x1000:0000, ss 指向 mbr 的栈, 因此要把ds,es,ss 全部设置为当前程序自己的
    ;自己的栈, 数据段都在头部段中, 已经由加载器修改完成了

    ;注意, 当前ds指向的是自己的头部段, 也就是0x1000
    mov ax,[ds:s_user_stack]    ;自己的栈
    mov ss,ax
    mov sp,user_stack_top       ;栈顶

    mov ax, [ds:s_user_header]  ;自己头部
    mov es,ax

    
    mov ax,[ds:s_user_data]     ;自己的数据段
    mov ds,ax

    

    ;显示自己数据段的一条信息
    push ds
    push data_msg
    call show_msg
    add sp,4


    ;段间跳转: jmp user_code_2 : start_2
    ;利用retf , 相当于 pop ip , pop cs
    push word [es:s_user_code_2]          ;段地址
    push word start_2                     ;偏移地址
    retf
    
    ;用户程序退出,返回到MBR中
    ;切换到MBR的栈, MBR栈中存放ip,cs 用于返回
    user_code_exit:
    mov ax,[es:mbr_stack]
    mov bx,[es:mbr_stack + 2]
    mov ss, bx
    mov sp,ax
    retf

    

;显示字符串, 需以0结尾
;参数: 字符串偏移地址, 字符串段地址
show_msg:
    push bp
    mov bp, sp
    push bx
    push es
    push ds
    push ax
    push si

    mov bx,[bp + 6]     ;段地址
    mov ds,bx

    mov bx, [bp + 4]    ;偏移地址
	
	mov ax,0xb800
    mov es,ax       ;显存首地址
    xor si,si
    
    .show_msg_loop:
        xor ax,ax
        mov al,[ds:bx]  ;检测是否是0
        or al,al         ; 自己or自己 => 自己, 由此来判断是否是0 , 以及显示此字符
        jz .show_msg_done
        mov [es:si],al
        mov byte [es:si + 1],0x07    ;添加字符属性
        inc bx
        add si,2
        jmp .show_msg_loop

    .show_msg_done:
    pop si
    pop ax
    pop ds
    pop es
    pop bx
    mov sp,bp
    pop bp
    ret


user_code_end:

;第二个代码段
SECTION user_code_2 align=16 vstart=0

    start_2:
        push word [es:s_user_code]      ;user_code 段地址
        push user_code_exit                  ;user_code 偏移
        retf                            ;pop ip , pop cs

user_code_2_end:


;数据段
SECTION user_data align=16 vstart=0
    data_msg db 'fuckme',0
user_data_end:

;栈段
SECTION user_stack align=16 vstart=0
    resw 128        ;resb 256           ;保留字节数 , res(b)字节 , res(w)字 , res(d)双字
user_stack_top:

;此段没有vstart=0. 因此标号pro_end从文件首开始计算
SECTION user_end align=16
pro_end:

