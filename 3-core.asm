;当前程序继承MBR的栈
;为了使用方便定义一些已知的段选择子.当然也可以从下面的头部间接获取


;地址对齐的一些操作:
;如果要与4字节(2^2)对齐,可以测试最低2位是否都为0,如果是则必定对齐
;如果要与512(2^9)对齐,可以测试最低9位是否都为0,如果是则必定对齐
;例如要对4字节对齐:
;   mov eax,5 ; test eax,3(11B); 结果是1,没有对齐
;可以这么做: 
;   mov eax,5
;   mov ebx,eax         ;把ebx向上取整为能被4所整除的数
;   and ebx,0xfffffffc  ;强制低2位都为0
;   add ebx,4           ;这个数必能被4整除, 相当于向上取整
;   test eax,11B        ;如果为0则能整除,为1则无法整除
;   cmovnz  eax,ebx     ;条件赋值, c(条件)mov(赋值)nz(不为0则赋值,否则不会赋值)


;*关于栈的内存分配*:
;1.
    ;从前面MBR中栈的分配: 基址:0x7c00, 段界限:0xffffe,G=1(以4k为单位)
    ;实际段界限:(0xffffe+1)*4096-1+1 = 0xFFFFF000
    ;实际最小偏移:0x7c00 + 0xFFFFF000 = 0x(1)00006C00 由于环绕特性,最高位舍去,最终:0x6c00
    ;esp最大:0xffffffff, 则最大偏移: 0x7c00 + 0xffffffff = 0x(1)00007BFF,最高位舍去:0x7bff
    ;最小:0x6c00, 最大:0x7bff. 可以看到这块4k内存,都在基址:0x7c00下面
    ;可以看到 栈一般情况下,都会因为环绕特性,其实际内存位置都在基址下面
;2.
;   下面alloc_mem是一个分配内存的段间过程,方向向上,像数组一样划空间
;   如果是给方向向上的段,可以工作的很好,但如果是给栈划空间,就需要配合建立描述符的过程一起工作了
;   假设栈请求分配内存: 
            ;       2.1 alloc_mem返回地址:0x100000, 给栈划分4k(0x1000)空间
            ;       2.2 下一个可用地址:0x100000+0x1000=0x101000
;   现在如果把0x100000 当成段描述的段基址,会发生错误
;   根据上面,栈的地址空间 一般(具体情况具体分析)情况都会在 段基址的下面
;   alloc_mem返回的地址空间应该在:0x100000 ~ 100FFF , 共计 4096 字节,这些属于栈
;   而0x100000的下面并不属于栈,如果把0x100000当成段基址,将覆盖0x100000之前的内存数据
;   因此,段基址应该是: 0x100000 + 4k(0x1000) = 0x101000
;   这样从0x100000 ~ 0x100FFF 都是栈空间



;--------------------
;常量定义


;重定位表中的每一项段信息占用12字节
REALLOC_TABLE_EACH_ITEM_BYTES EQU 12

;符号信息表每项占用16字节
SYMBOL_TABLE_EACH_ITEM_BYTES equ 16

;用户符号信息表每项占用12字节
USER_SYMBOL_TABLE_EACH_ITEM_BYTES EQU 12

;用户程序扇区号
USER_APP_SECTOR EQU 100 


;MBR中定义
SEL_4G_DATA equ 0x18    ;数据段
SEL_STACK EQU 0x20      ;栈
SEL_0XB8000 EQU 0x10    ;显存
SEL_MBR EQU 0X08        ;MBR段

;当前程序的,由MBR创建
SEL_HEADER EQU 0x28 ; 头部段选择子
SEL_CODE EQU 0x30   ;代码段
SEL_DATA EQU 0X38   ;数据段
SEL_FUNC EQU 0X40   ;函数段


;--------------------

;function 函数段内大部分都是段间过程调用
;每个过程结尾都是 retf (pop eip, pop cs)
;每个retf 后都加了立即数,恢复栈,不用自己恢复esp
;调用function段的段间过程需要 : call SEL_FUNC:过程名 => push cs, push eip

;重定位表含当前程序的4个段信息
;每个段信息包含段界限,段基址,段属性,每个属性4字节,3个属性算一项共12字节


[bits 32]
section header vstart=0 align=16
    ;程序长度
    app_len dd tail_end     ;0x00

    ;入口点偏移,段地址
    ;当此程序被加载后,物理段地址被替换成段选择子
    entry   dd start                ;0x04
            dd section.code.start   ;0x08

    ;重定位表有几项
    realloc_table_len dd  (table_end - table_start)/REALLOC_TABLE_EACH_ITEM_BYTES ;0x0c

    ;重定位表
    ;重定位表中存放了每个段的 : 段基址,段界限(段长度-1),段属性
    ;被加载程序处理后,所有的段基址都将被替换成段选择子
    table_start:
        ;头部段
        seg_header_len dd header_end-1  ;段界限, 0x10
        seg_header_addr dd section.header.start ;段基址, 0x14
        seg_header_attr dd 0x00409200           ;段属性, 0x18

        ;代码段
        seg_code_len dd code_end-1      ;段界限,0x1c
        seg_code_addr dd section.code.start ;段基址,0x20
        seg_code_attr dd 0x00409800         ;段属性,0x24

        ;数据段
        seg_data_len dd data_end-1      ; 段界限,0x28
        seg_data_addr dd section.data.start ;段基址,0x2c
        seg_data_attr dd 0x00409200         ;段属性,0x30

        ;函数段
        seg_function_len  dd function_end-1 ;段界限,0x34
        seg_function_addr dd section.function.start ;段基址,0x38
        seg_function_attr dd 0x00409800     ;属性,0x3c

    table_end:

    ;----------------
    ;以下段选择子由mbr传递过来

    ;4G数据段
    seg_4g_data dd 0        ;0x40
    ;栈段
    seg_stack   dd 0        ;0x44
    ;显存段
    seg_0xb8000 dd 0        ;0x48
    ;MBR段
    seg_mbr     dd 0        ;0x4c
header_end:

section code vstart=0 align=16
    start:
    ;当前栈段,ss:0x20,继承使用了MBR的栈
    
    ;切换DS, 直接使用上面定义的常量,省的去头部段拿了
    mov eax,SEL_DATA
    mov ds,eax

    ;显示消息,内核启动
    mov ebx,first_msg_done - first_msg  ;字符串长度
    push ebx
    push ds
    push dword first_msg            ;起始地址
    ;call 段选择子:过程名
    ;具体过程:
    ;1.push cs, push eip
    ;2.根据SEL_FUNC,获取索引8 *8 + GDTR提供的GDT起始地址:
    ; 2.1  地址: 8*8 + 0x7e00 ,检查此地址是否越界(GDT的界限)
    ; 2.2  获取此地址的段描述符,加载到cs高速缓冲区
    ;3.查看print偏移地址是否在此段内,越界检查 (描述符的界限)
    ;4.mov eip, print
    call SEL_FUNC:print
    ;add esp,0x0c . 不需要手动还原栈,段间调用都加了retf N 来恢复栈

    ;加载用户程序
    call SEL_FUNC:load_app

    ;显示加载完毕信息
    mov ebx,loaded_msg_done - loaded_msg    ;长度
    push ebx
    push ds
    push dword loaded_msg
    call SEL_FUNC:print


    ;加载完成, 跳转到用户程序

    ;保存栈顶, 用户程序回来后恢复
    mov [ds:stack_top], esp
    
    ;获取头部段选择子.进行跳转
    mov eax,[ds:user_header_selector]
    mov es,eax
    jmp far [es:0x04]  


exit_process:
    ;------用户程序退出后应该还需要把分配的内存收回
    ;------用户描述符全部删除, 修改gdt_size, 重新加载gdt,这里全部省略

    ;恢复自己的数据段
    mov eax,SEL_DATA
    mov ds,eax
    ;恢复栈
    mov ebx,[ds:stack_top]
    mov eax,SEL_STACK
    mov ss,eax
    mov esp,ebx

    ;喊一句话
    mov ebx,(back_msg_done - back_msg)
    push ebx
    push ds
    push dword back_msg
    call SEL_FUNC:print
    
    hlt

code_end:

section function vstart=0 align=16

;退出
exit:
    push SEL_CODE
    push exit_process
    retf

;加载一个程序
load_app:
    push ebp
    mov ebp,esp
    pushad
    push es
    push ds

    ;首先读取一个扇区,获取用户程序的头部信息
    ;由于需要动态给用户程序分配内存地址,因此不再直接把首个扇区读到指定内存地址
    ;加载用户头部的缓冲区在 自己的data段 : user_header_buffer 定义了512字节
    mov eax,SEL_DATA
    mov ds,eax
    mov ebx,user_header_buffer

    push ds                 ;段选择子
    push ebx                ;偏移
    push dword USER_APP_SECTOR  ;扇区号
    call SEL_FUNC:read_sector

    ;获取程序多长
    mov eax,[ds:user_header_buffer] ;长度
    xor edx,edx
    mov ecx,512
    div ecx

    ;计算还需要读取几个扇区
    or edx,edx          ;是否有余数,有余数则+1
    jz .begin_alloc_mem
    inc eax             ;有余数

    ;为用户程序分配内存地址
    .begin_alloc_mem:
    mov ecx,eax         ;备份扇区数
    ;计算字节数
    xor edx,edx
    mov ebx,512
    mul ebx             ;计算字节数, eax 32位4G空间足够,不需要edx

    push eax            ;需要分配的字节数
    call SEL_FUNC:alloc_mem     ;返回eax 为可用的起始地址,用户程序将被加载到这
    mov edi,eax                 ;保存一份起始地址

    ;把用户程序读取到 eax为起始地址的内存空间中
    push SEL_4G_DATA            ;4g 空间    
    push eax                    ;用户程序起始地址
    push ecx                    ;扇区数量
    push USER_APP_SECTOR        ;起始扇区号
    call SEL_FUNC:read_user_app ;读取整个用户程序

    ;读完用户程序,需要给程序的每个段创建描述符,才能让用户程序运行起来
    push SEL_4G_DATA        ;段选择子
    push edi                ;用户程序被加载的起始地址
    call SEL_FUNC:create_user_gdt   ;为用户程序创建描述符和栈空间

    ;把头部段选择子保存一份,后续需要用到
    mov eax,SEL_4G_DATA
    mov es,eax          ;指向4G
    mov eax,[es:edi + 0x14] ;头部段选择子
    mov [ds:user_header_selector],eax   

    ;用户程序符号表处理
    ;使用头部段选择子, 当然也可以使用SEL_4G_DATA + 用户程序起始地址来处理头部符号表(这样稍显麻烦)
    push eax
    call SEL_FUNC:realloc_user_app_symbol_table


    pop ds
    pop es
    popad
    mov esp,ebp
    pop ebp
    retf


;比较字符串
;参数:目标偏移,目标段选择子,    原偏移,  原段选择子 , 字符串长度
;栈中的位置:12       16          20        24        28
;返回:eax , 0:不相等, 1:相等
compare_string:
    push ebp
    mov ebp,esp
    pushfd
    push es
    push ds
    push esi
    push edi
    push ecx
	push edx

    mov eax,[ebp + 16]      ;目标段选择子
    mov es,eax
    mov edi,[ebp + 12]      ;目标偏移

    mov eax,[ebp + 24]      ;原段选择子
    mov ds,eax  
    mov esi,[ebp + 20]      ;原偏移

    mov ecx,[ebp + 28]      ;字符串长度
	
	mov edx,1
    xor eax,eax
    cld
    repe cmpsb
    cmovz eax,edx             ;匹配成功


    .compare_string_done:
	pop edx
    pop ecx
    pop edi
    pop esi
    pop ds
    pop es
    popfd
    mov esp,ebp
    pop ebp
    retf 20

;符号表字符串比较
;参数:用户信息表地址偏移,用户信息表头部段选择子,    原信息表偏移,  原信息表段选择子 
;栈中的位置:8                   12                16        20
;返回:eax , 0:不相等, 1:相等
symbol_table_item_compare_string:
    push ebp
    mov ebp,esp
    pushfd
    push es
    push ds
    push edi
    push esi

    mov eax,[ebp + 20]      ;原信息表段选择子 
    mov ds,eax
    mov esi,[ebp + 16]      ;原信息表偏移

    mov eax,[ebp + 12]      ;目标信息表段选择子
    mov es,eax
    mov edi,[ebp + 8]       ;目标信息表地址偏移

    xor eax,eax

    ;先比较字符串长度
    ;4字节比较. 比较esi,edi指向的字符串长度,每一项首地址都是4字节的字符串长度
    push edi
    push esi
    cld
    cmpsd               ;比较后 esi+=4, edi+=4. 会自动增加
    pop esi
    pop edi               
    jnz .symbol_table_item_compare_string_done

    ;长度一致,进行字符串比较
    push dword [es:edi]     ; 首4个字节为字符串长度
    push ds           ;原段
    push dword [ds:esi+4]   ;原偏移在每项首地址的后4个字节,存放了实际字符串的地址
    push es           ;目标段
    push dword [es:edi+4]   ;目标偏移,偏移+4,存放字符串的地址
    call SEL_FUNC:compare_string    ;比较字符串

    
    .symbol_table_item_compare_string_done:
    pop esi
    pop edi
    pop ds
    pop es
    popfd
    mov esp,ebp
    pop ebp
    ret 16

;比较用户符号信息表
;参数:用户地址表起始地址, 用户信息表地址, 用户头部段选择子
;栈中位置: 8                12              16
;拿用户信息表的一条与当前可以导出的信息表全部项进行比较
symbol_table_item_compare_and_fill:
    push ebp
    mov ebp,esp
    pushad
    pushfd
    push es
    push ds

    mov eax,[ebp + 16]      ;用户头部段选择子
    mov es,eax             
    mov edi,[ebp + 12]      ;用户信息表地址

    mov eax,SEL_DATA
    mov ds,eax                  ;ds指向自己数据段
    mov esi,symbol_table_begin  ;指向自己的信息表首项地址
    mov ecx,[ds:symbol_table_len]  ;自己的信息表共几项

    ;循环当前可导出的符号表每一项
    .begin_comapre_string:
        push ds           ;原信息表段选择子
        push esi                ;原信息表偏移地址
        push es           ;用户头部段选择子
        push edi                 ;用户信息表偏移(首)地址
        call symbol_table_item_compare_string
        or eax,eax
        jnz .matched      ;匹配成功,跳转
        add esi,SYMBOL_TABLE_EACH_ITEM_BYTES
    loop .begin_comapre_string

    jmp .symbol_table_item_compare_and_fill_done    ;没匹配到

;匹配成功
.matched:
    push ds       ;原段选择子
    push esi      ;原信息表偏移地址
    push es       ;用户段选择子
    push edi      ;用户信息表偏移地址
    push dword [ebp + 8]   ;用户地址表
    call symbol_table_item_fill_addr    ;填充地址


.symbol_table_item_compare_and_fill_done:
    pop ds
    pop es
    popfd
    popad
    mov esp,ebp
    pop ebp

    ret 0x0c

;填充地址
;参数:用户地址表,用户信息表地址,用户信息表段选择子, 原信息表地址, 原段选择子
;栈中位置: 8            12              16          20          24
symbol_table_item_fill_addr:
    push ebp
    mov ebp , esp
    pushad
    push es
    push ds

    mov eax,[ebp + 24]      ;原段选择子
    mov ds,eax  
    mov esi,[ebp + 20]      ;原信息表地址

    mov eax,[ebp + 16]      ;用户段选择子
    mov es,eax
    mov edi,[ebp + 12]       ;用户信息表地址

    mov edx,[ebp + 8]       ;用户地址表首地址

    ;当前可导出的信息表结构:
    ; 字符串长度 , 4字节
    ; 字符串偏移地址, 4字节
    ; 字符串对应的过程地址, 4字节    -> 这个位置是要获取的, 原信息表起始地址+8
    ; 索引 , 4字节

    mov ebx,[ds:esi + 8]        ;内核数据段的地址表项,此偏移地址存放着偏移地址,段选择子

    ;根据用户信息表项内的索引,确定用户地址表的位置,然后进行填充偏移地址,段选择子
    mov ecx,[es:edi + 8]        ;用户信息表项的索引
    shl ecx,3                   ;乘8. 用户地址表每一项占8字节, 索引*8 => 相当于左移3位

    mov eax,[ds:ebx]            ;获取过程偏移地址
    mov [es:edx + ecx],eax      ;在用户地址表中存放偏移地址

    movzx eax, word [ds:ebx + 4]       ;过程的段选择子, 内核定义的地址表中段选择子是2个字节
    mov [es:edx + ecx + 4], eax  ;在用户地址表中存放段选择子

    pop ds
    pop es
    popad
    mov esp,ebp
    pop ebp

    ret 20

;用户符号表处理
;参数: 头部段选择子
realloc_user_app_symbol_table:
    push ebp
    mov ebp,esp
    pushad
    push es

    mov ebx,[ebp + 12]  ;头部段选择子
    mov es,ebx
    

    ;比较过程:
    ;拿用户程序的符号信息表与自己数据段中的符号信息表中的每一项比较
    ;如果匹配,则把自己数据段中的符号地址表(偏移,段选择子)填充到用户的符号地址表中

    ;用户符号信息表起始位置 0x3c
    mov ecx,[es:0x3c]

    mov esi,[es:0x40] ;   用户符号信息表首项地址

    mov edi,[es:0x44] ;   用户符号地址表起始地址

    .compare_start:
        push es             ;用户头部段选择子
        push esi            ;用户符号信息表首项地址
        push edi            ;用户符号地址表起始地址
        call symbol_table_item_compare_and_fill
        add esi,USER_SYMBOL_TABLE_EACH_ITEM_BYTES   ;指向下一个符号信息表内的起始地址
    loop .compare_start
    
    
    pop es
    popad
    mov esp,ebp
    pop ebp

    retf 4

;为用户程序创建描述符
;参数: 用户程序被加载的起始地址, 段选择子
create_user_gdt:
    push ebp
    mov ebp,esp
    pushad
    push es

    mov eax,[ebp + 16]  ;段选择子
    mov es,eax  
    mov ebx,[ebp + 12]  ;被加载的起始地址, 指向头部

    mov ecx,[es:ebx + 0x0c] ;获取重定位表项数
    mov esi,0x10            ;用户程序头部重定位表的起始地址
    ;处理重定位表
    .process_realloc_table:
        mov eax,[es:ebx+esi+4]          ;段基址
        add eax,ebx                     ;实际段基址

        push eax                        ;段基址
        push dword [es:ebx + esi]       ;段界限
        push dword [es:ebx + esi + 8]   ;段属性
        call SEL_FUNC:make_gd           ;返回描述符, edx:eax

        push edx                        ;高32位
        push eax                        ;低32位
        call SEL_FUNC:add_to_gdt        ;加入到GDT中,返回ax(段选择子)

        ;把段选择子写入用户程序中
        mov [es:ebx + esi + 4],eax
        ;指向重定位表中的下一项
        add esi,USER_SYMBOL_TABLE_EACH_ITEM_BYTES   
    loop .process_realloc_table

    ;重定位表处理完毕
    ;把入口点的段基址替换成段选择子
    mov eax,[es:ebx+0x20]   ;此处在上面重定位表中已经替换完成
    mov [es:ebx+0x08] , eax

    ;为用户程序创建栈空间
    push es
    push ebx
    call SEL_FUNC:create_stack  ;创建栈,并构建栈描述符加入到GDT中


    pop es
    popad
    mov esp,ebp
    pop ebp

    retf 8

;创建栈
;参数:用户程序起始地址, 段选择子
create_stack:
    push ebp
    mov ebp, esp
    pushad
    push es

    mov eax,[ebp + 16]  ;段选择子
    mov es,eax  
    mov ebx,[ebp + 12]  ;被加载的起始地址, 指向头部

    ;ecx:指定栈的界限
    mov ecx,0xfffff     ;最大界限
    mov eax,[es:ebx + 0x34] ;获取栈指定的大小
    sub ecx,eax    ;减去栈指定的长度,这样就得到了栈的最小偏移
    ;edx:指定栈的属性
    mov edx,0x00c09600  ;G=1,E=1,方向往下的数据段

    ;下面调用alloc_mem 来分配一个段基址
    ;首先确定需要分配多大的空间, 根据上面的eax获取到的以4K为单位的数值*4096即可
    ;4096=(2^12).因此左移12次
    shl eax,12
    mov esi,eax                 ;备份,等地址返回后需要用到
    push eax
    call SEL_FUNC:alloc_mem     ;返回eax, 可用地址

    ;把基址提高N字节,此地址相当于下一个alloc_mem分配的内存地址
    ;把此地址当成段基址
    add eax,esi                 ;由于地址环绕特性,如果不这样做会覆盖掉前面的内存数据,具体在上面已经写过了

    ;为栈创建描述符
    push eax            ;段基址
    push ecx            ;段界限
    push edx            ;段属性
    call SEL_FUNC:make_gd       ;返回edx:eax

    push edx
    push eax
    call SEL_FUNC:add_to_gdt    ;增加到GDT中,返回eax 段选择子

    ;把段选择子写回用户程序
    mov [es:ebx + 0x38], eax

    pop es
    popad
    mov esp,ebp
    pop ebp

    retf 8

;把8字节的描述符加入到GDT中
;参数:低32位,高32位
;返回eax, (ax有效位)段选择子
add_to_gdt:
    push ebp
    mov ebp,esp
    push es
    push ds
    push esi
    push ebx

    mov esi,SEL_DATA
    mov ds,esi          ;指向自己的数据段,获取用于获取 GDT_SIZE ,GDT_BASE
    mov esi,SEL_4G_DATA
    mov es,esi          ;指向4G,用于增加描述符

    sgdt [ds:gdt_size]  ;存放GDTR所存的值,6字节

    xor esi,esi
    xor ebx,ebx
    mov bx, word [ds:gdt_size]   ;获取GDT界限
    inc bx                  ;指向下一个可存放的偏移地址
    mov esi,[ds:gdt_base]   ;GDT起始地址
    add esi,ebx             ;可存放描述符的地址

    ;增加描述符到GDT
    mov ebx,[ebp + 12] ;低32位描述符
    mov [es:esi],ebx
    mov ebx,[ebp + 16]  ;高32位
    mov [es:esi + 4],ebx

    add word [ds:gdt_size],8 ;增加界限
    lgdt [ds:gdt_size]  ;重载GDT, 使之生效

    ;构造描述符的段选择子
    ;获取界限, 除以8(右移3位) , 得到索引
    xor eax,eax
    mov ax,[ds:gdt_size]   
    shr ax,3               ;得到索引
    ;由于当前是在GDT中,TI位置0,DPL忽略,因此左移3位即可
    shl ax,3

    pop ebx
    pop esi
    pop ds
    pop es

    mov esp,ebp
    pop ebp

    retf 8

;根据:段基址,段界限,段属性创建一个描述符
;参数: 段属性, 段界限, 段基址
;返回: edx:eax 一个8字节描述符,edx高32位,eax低32位
make_gd:
    push ebp
    mov ebp,esp
    push ecx
    push ebx
    
    mov eax,[ebp + 20]  ;段基址
    mov ebx,[ebp + 16]  ;段界限(低20位有效位)
    mov ecx,[ebp + 12]  ;段属性

    mov edx,eax        
    shl eax,16      ;保留低16位段基址
    or ax,bx        ;eax 描述符低32位合成完毕

    and edx,0xffff0000  ;保留高16位
    rol edx,8           ;循环左移,把高8位移动到低8位
    bswap edx           ;交换低地址和高地址. 段基址位置存放完毕

    and ebx,0x000f0000  ;段界限保留高4位
    or edx,ebx          ;段界限合成完
    or edx,ecx          ;组合属性

    
    pop ebx
    pop ecx
    mov esp,ebp
    pop ebp
    retf 0x0c

;读取整个用户程序
;参数: 起始扇区号,扇区数量,程序被加载的起始地址,目标内存段选择子(注:此选择子一般情况是SEL_4G_DATA)
read_user_app:
    push ebp
    mov ebp,esp
    pushad
    push es

    mov ecx,[ebp + 16]      ;扇区数量
    mov edx,[ebp + 12]      ;起始扇区号
    mov ebx,[ebp + 20]      ;程序被加载的起始地址 , 是内存分配出来的地址
    mov eax,[ebp + 24]      ;段选择子
    mov es,eax              ;一般情况是SEL_4G_DATA. 指向4G空间

    .read_one_sector:
        push es                 ;段选择子
        push ebx                ;偏移, ebx在read_sector中自增
        push edx                ;扇区号
        call SEL_FUNC:read_sector
        inc edx                 ;读取下一个扇区
    loop .read_one_sector



    pop es
    popad
    mov esp,ebp
    pop ebp

    retf 0x10


;分配一块内存
;参数: 需要多少字节
;返回: eax :一个以4字节对齐的内存起始地址
alloc_mem:
    push ebp
    mov ebp,esp
    push ds
    push ebx
    push ecx
    
    mov eax,[ebp + 12]  ;参数
    mov ebx,SEL_DATA
    mov ds,ebx

    mov ebx,[ds:user_mem_base_addr] ;获取可用的内存地址, ebx 此地址用于返回
    add eax,ebx                     ;计算下一个可用地址

    ;让下一个内存地址是4字节对齐的, 也就是能被4整除的,即低2位都是0
    mov ecx,eax     ;确保ecx一定能被4整除
    and ecx,0xfffffffc  ;强制低2位都是0
    add ecx,4           ;这个数一定能被4整除

    ;看看eax是否能被4整除, and eax,3, 如果不为0说明无法被4整除
    test eax,3          ;3的二进制:11
    cmovnz eax,ecx      ;不为0,则把能整除的ecx赋值给eax

    ;为下一个可用地址赋值
    mov [ds:user_mem_base_addr],eax
    
    xchg eax,ebx


    pop ecx
    pop ebx
    pop ds
    mov esp,ebp
    pop ebp

    retf 4
;读取扇区
;参数: 扇区号,目标偏移地址, 目标段选择子
;返回 ebx 以一个可写入的地址

;端口: 0x1f2 用来设置扇区数量
;0x1f3 - 0x1f6  用来设置扇区号, 其中0x1f6只有低4位是最后的扇区号
;0x1f7 用来控制读/写, 反馈状态
;0x1f0 用来读取数据 
;28位扇区号,LBA模式
read_sector:
    push ebp
    mov ebp,esp

    push eax
    push es
    push edx
    push ecx

    mov eax,[ebp + 20]  ;段选择子
    mov es,eax
    mov ebx,[ebp + 16]  ;偏移地址
    mov eax,[ebp + 12]  ;扇区号

    push eax
    mov dx,0x1f2    ;设置扇区数
    mov al,1
    out dx,al       

    inc dx          ;0x1f3
    pop eax
    out dx,al       

    inc dx          ;0x1f4
    shr eax,8       ;去掉低8位
    out dx,al

    inc dx          ;0x1f5
    shr eax,8
    out dx,al

    inc dx          ;0x1f6
    shr eax,8
    and al,0000_1111B   ;保留低4位有效位
    or al,0xe0          ;1110_000B , LBA模式,从主盘读
    out dx,al

    inc dx          ;0x1f7
    mov al,0x20     ;读取状态
    out dx,al

    ;查看硬盘状态
    .read_disk_status:
        in al,dx
        and al,1000_1000b   ;检查是否可读
        cmp al,0000_1000b   ;如果第三位为1,则可读
        jnz .read_disk_status   ;否则继续检查
    
    ;从0x1f0中开始读取
    mov dx,0x1f0
    mov ecx,256
    .begin_read:
        in ax,dx
        mov [es:ebx],ax
        add ebx,2
    loop .begin_read


    
    pop ecx
    pop edx
    pop es
    pop eax

    mov esp,ebp
    pop ebp
    retf 0x0c

;打印到显存 
;参数:偏移地址,段选择子,字符串长度
print:
    push ebp
    mov ebp,esp

    push ds 
    push es
    push esi
    push edi
    push ecx
    push eax
    
    mov esi,[ebp + 12]   ;偏移
    mov ecx,[ebp + 16]  ;段选择子
    mov ds,ecx
    mov ecx,[ebp + 20]  ;长度

    ;获取最后一次的打印位置
    mov eax,SEL_DATA
    mov es,eax
    xor edi,edi
    mov di,[es:print_pos]      ;从此偏移开始打印

    ;设置显存段
    mov eax,SEL_0XB8000
    mov es,eax

    .print_loop:
        mov al,[ds:esi]
        mov [es:edi],al
        inc di
        mov byte [es:edi],0x07
        inc esi
        inc di
    loop .print_loop

    .print_done:
        mov eax,SEL_DATA
        mov es,eax
        mov [es:print_pos],edi
    

    pop eax
    pop ecx
    pop edi
    pop esi
    pop es
    pop ds

    mov esp,ebp
    pop ebp
    retf 0x0c   ;pop eip , pop cs

function_end:

section data vstart=0 align=16

    first_msg db 'fuck !'
    first_msg_done:

    loaded_msg db 'loaded!!!'
    loaded_msg_done:

    back_msg db 'Im back!!!!!!!'
    back_msg_done:

    ;栈顶,备份. 为了跳转回来后还原
    stack_top dd 0

    ;print_pos : 当前打印的位置
    print_pos dw 0

    ;由于加载用户程序后会添加描述符,需要更改gdt_size
    ;sgdt 指令用于存放gdt数据
    gdt_size    dw 0    ;界限
    gdt_base    dd 0    ;GDT起始地址

    ;用户程序被加载到的地址,1M开始处
    user_mem_base_addr  dd  0x100000

    ;用户头部段选择子,用于后续跳转
    user_header_selector    dd  0
    
    ;用于读取用户程序首个扇区
    user_header_buffer times 512 db 0

    ;符号信息表的项数
    symbol_table_len dd (symbol_table_end - symbol_table_begin) / SYMBOL_TABLE_EACH_ITEM_BYTES

    ;可导出可被连接(用户程序可见可用)的符号信息表
    symbol_table_begin:
        print_info: 
                   dd (read_sector_string - print_string)   ;字符串长度(用于比较)
                   dd print_string      ;字符串的偏移(用于匹配)
                   dd print_addr        ;过程地址
                   dd 0                 ;索引 (这里没用到)

        read_sector_info:    
                            dd (make_gd_string - read_sector_string)
                            dd read_sector_string   
                            dd  read_sector_addr
                            dd  1
        
        make_gd_info:    
                        dd (exit_string - make_gd_string)
                        dd make_gd_string
                        dd make_gd_addr
                        dd 2

        exit_info:       
                        dd (compare_string_string - exit_string)
                        dd exit_string
                        dd exit_addr
                        dd 3

        compare_string_info:
                        dd (symbol_table_string_end - compare_string_string)
                        dd compare_string_string
                        dd compare_string_addr
                        dd 4

    symbol_table_end:

    ;字符串表
    symbol_table_string_begin:
        print_string db 'print'
        read_sector_string db 'read_sector'
        make_gd_string db 'make_gd'
        exit_string db 'exit'
        compare_string_string db 'compare_string'
    symbol_table_string_end:

    ;地址表
    symbol_table_addr_begin:
        print_addr  dd  print           ;偏移
                    dw  SEL_FUNC        ;段选择子

        read_sector_addr dd read_sector
                         dw SEL_FUNC

        make_gd_addr    dd make_gd
                        dw SEL_FUNC

        exit_addr   dd  exit
                    dw SEL_FUNC
        
        compare_string_addr dd compare_string
                            dw SEL_FUNC
    symbol_table_addr_end:
    
data_end:

section tail
tail_end:
