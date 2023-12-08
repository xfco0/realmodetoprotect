;------------------------新增--------------------------------

; 本文件涉及了权限, 将使用调用门描述符来处理 低权限到高权限的转移

;------------------------权限----------------------------
;此文件延用上个CORE.asm. 并做出一些修改
;由于此文件涉及了特权, RPL,DPL,CPL, 因此有些地方会额外做出说明
;RPL: CPU提供的一个参数,由操作系统来做主,意思是希望以哪种特权去访问
;CPL: 当前正在执行的代码段的特权级 , 也是描述符中的DPL (只是在不同状态下的名称)
;DPL: 描述符的DPL

;-----------------------调用门描述符----------------------------
;上个CORE.ASM中, 加载用户程序后,为用户创建的描述符DPL=0.为用户填充重定位地址表的段选择子RPL=0
;用户程序相当于工作在特权0上. 此文件中,将把用户程序设定为特权3.
;由于当前用户程序的特权级是3,因此 用户程序地址重定位表也需要全部修改
;function段描述符C=0,是非一致性代码段,想要直接调用非一致性代码段: CPL=DPL.必须是同级, 但此时用户程序CPL=3
;本文件使用调用门:Call Gate 来处理这个问题
;调用门(Call Gate)就是一个描述符,格式:
; 31  ~  16            15  14 ~ 13  12     11 ~ 8          7 ~  5  4  ~  0
; 段内偏移高16位        P    DPL     S:0   TYPE(1100)        000     参数个数
; 31 ~  16         15 ~ 0
; 段选择子       段内偏移低16位

; 调用门 TYPE 固定1100
; 调用门描述符的段选择子和偏移地址都是已知的某个代码段的选择子和偏移
; 描述符的参数个数 在符号地址表中给出每个过程需要的参数个数

; 调用门的作用就是: 间接访问某个高特权代码段(通过段选择子)的某个过程(偏移地址)
; 通过描述符结构可以看出来, 调用门就是为一个代码段中的某一个过程服务的.
; 对于本文件就是: 一个调用门对应 function段的一个过程

; 使用调用门也是有权限的 : 门描述符的DPL.
;   1.只有当 当前调用者的CPL<=门DPL,RPL <= 门DPL才能访问门描述符
;   2.对于一致性代码段: CPL>=目标代码段DPL, 不论JMP,CALL, 转移后CPL不变,栈不变
;   3.对于非一致性代码段: 
;       3.1. CALL指令要求: CPL >= 目标代码段DPL , CPL变成目标代码段DPL, 切换栈
;       3.2. JMP 指令: CPL = 目标代码段DPL , CPL不变,栈不变

; 使用调用门: call far 调用门选择子, jmp far 调用门选择子
; 由于目标段的偏移地址和目标段选择子已经在门描述符中, 一旦检查通过后
; 根据门描述符中的段选择子的TI位,找到对应的段描述符, 把段描述符加载到cs (这里的意思是调用门可以放在GDT或LDT)
; 最后根据段描述符的基址+ 门描述符的偏移 开始执行代码


;------------------------------ 门描述符,TSS描述符和LDT描述符---------------
; 调用门描述符,TSS描述符和LDT描述符 都是系统段描述符(S位=0)
; 调用门TYPE:1100, LDT TYPE:0010 , TSS TYPE:1001

;------------------------------TSS,LDT--------------

; LDT:局部描述符表. 类似GDT,用于存放描述符. 每个任务的描述符分开管理,都在自己的LDT中
; TSS是一种结构,用来表示一个任务,用于任务的切换,也用于特权栈的切换(低特权到高特权的代码段运行)

; 要使用TSS,必须为TSS创建描述符,且必须存放在GDT中
; 要使用LDT,必须为LDT创建描述符,且必须存放在GDT中
; LDT与GDT一样需要 16位界限,32位基址. 但跟加载GDT的指令lgdt不一样的是,加载LDT指令:[lldt LDT段选择子]
; 也就是16位界限与32位基址被存放在描述符中

; LDT描述符,TSS描述符需要被存放在GDT中.
; GDT并不是一个段描述符, GDT就是一个线性地址上存放着描述符的结构
; LDT描述符的属性:S=0,TYPE=0010
; TSS描述符的属性:S=0,TYPE=1001( 1011 表示繁忙) , 只要当前CPL <= TSS描述符的DPL,就可以访问此描述符,这意味着只要 CPL<=TSS.DPL 就可以调度任务


; CPU厂商建议使用LDT,TSS来管理一个任务
; 实际情况是TSS是必须的, 毕竟TSS 表示这个任务.  切换任务需要用到TSS, 特权级栈改变也需要TSS
; 而LDT并不是必须品,是否使用LDT取决于你. (可以把任务的段描述符扔在GDT中)


; TR寄存器指明当前任务, LTR 指令用于加载一个TSS段选择子 到TR , 同时把描述符中的TYPE从1001变成1011(繁忙状态)
; 此时虽然TSS是繁忙状态, TR也准备好了, 但任务并没有切换

; LTR指令: LTR TSS段选择子 => TR: TSS段选择子

; LLDT 指令用于加载一个LDT 到 LDTR寄存器
; LLDT指令: LLDT LDT段选择子   => LDTR: LDT段选择子
; 一旦LLDT 加载完成,  此局部描述符表就生效了, 可以访问此LDT中的描述符了



;------------------------------

;------------------------符号地址表的修改--------------------------------------
; section data中的 : symbol_table_addr_begin
; 每一项后都增加一个dw字段的门描述符, 在内核启动后,会为所有的符号地址表中的过程创建调用门描述符
; 在与用户程序的符号匹配后, 原来的做法是将 偏移地址和段选择子 填充到用户地址表中
; 现在将 已经创建的好的调用门选择子 写入到用户地址表中

;--------------------------------------------------------------

;---------------------新增过程:create_call_gated---------------------------
; 为符号地址表中每个过程创建 调用门描述符, 并增加到GDT中
; 同时将 调用门的选择子 填充到自己的地址表中, 用于把 选择子 在与用户程序匹配后写入到用户程序地址表中
; 调用门描述符的DPL 根据参数来决定,当前是: 3 (用户程序特权)
; 由于 门选择子 不一定给谁用, 因此一开始在 自己地址表中的门选择子 默认RPL=0
; 给用户程序用的时候, 将修改RPL
;
;--------------------------------------------------------------

;---------------------新增LDT----------------------------
;LDT是局部描述符表, 每个任务都可以有
;LDT专门用于管理每一个任务的段描述符, 而不是像之前那样把所有的描述符全部扔在GDT中
;GDT全局唯一, LDT可以有很多. 
;为了跟踪每一个LDT, 一旦任务的段描述符在LDT中全部存放好后,也就是确定了LDT的界限后
;需要为LDT创建一个描述符(S位=0), 这是一种系统段描述符
;LDT的描述符结构完全与段描述符一致, 唯一需要注意的是 S:0, TYPE:0010
;由于每一个任务,都维护了一块TCB,用来跟踪任务的所有基本信息
;因此下面为LDT创建描述符的时候, 只需要注意 LDT的属性设置即可
;下面代码LDT的属性: P=1,S=0,TYPE=0010,DPL=0(只能给特权0访问)
;LDT属性:0x00008200

;---------------------;---------------------

;----------------- 新增TSS ------------------------
; TSS 是一种结构 .  用于表示一个任务, 也用于特权栈的切换(低特权到高特权的调用)
; 为了使用TSS, 需要为TSS创建一个描述符,并把描述符存放在GDT中
; TSS 在切换任务的时候会把当前任务的所有寄存器保存在自己的结构中,以便在下一次恢复的时候继续执行代码
; TR 寄存器 表示当前任务, TR 保存着TSS的 段选择子
; 使用LTR 来加载TSS段选择子 到TR寄存器

;-----------------;-----------------

;----------------------新增TCB,任务控制块--------------------------------
;为每个任务(一个用户程序), 单独创建一块内存空间(并不是读取用户程序的内存),管理此任务,为了TSS和LDT
;此任务块中包含了 此用户程序的基本信息, 一个任务块对应一个用户程序
;由于可以多任务,因此新过程:create_tcb_and_append_to_tcblinklist
;把每一个TCB连接在一起,形成链表;
;TCB结构:
;0x00: 下一个TCB地址
;0x04:状态 ; 0x06:程序基址
;0x0a:LDT 界限 ; 0x0c:LDT基址
;0x10:LDT 选择子
;0x12:TSS界限,0x14:TSS基址,0x18:TSS 选择子
;0x44:用户头部段选择子

;0x1A:特权0 栈长度,以4K为单位; 通过这个数可以用 : 0xfffff - 此长度 => 栈段的界限
;0x1E:特权0, 栈基址
;0x22:特权0, 栈选择子
;0x24:特权0, 栈esp

;0x28:特权1 栈长度
;0x2c:特权1 栈基址
;0x30:特权1 栈选择子
;0x32:特权1 栈esp

;0x36:特权2 栈长度
;0x3a:特权2 栈基址
;0x3e:特权2 栈选择子
;0x40:特权2 栈esp
;--------------------------------------------------------------

;-------------------------------加载用户程序的流程修改-------------------------------
;在之前通过 load_app 加载用户程序,为用户程序创建的段描述符全部存放在GDT中
;现在将把段描述符存放在LDT中, LDT:局部描述符表
;让每一个用户程序各管各的, 分别独立在自己的LDT, GDT只放内核程序的东西
;LDT可以有很多个, 不像GDT只有一个
;LDT 对应的寄存器是LDTR, 每当CPU运行此任务时,就会切换LDTR,让LDTR指向当前的LDT
;因此当前 每加载一个用户程序就会为其创建一个新的LDT,并把用户程序的段描述符全放在自己的LDT中
;LDT与GDT一样, 需要基址(4字节)和界限(2字节),因此1个LDT最多可以有8192个描述符
;唯一的不同就是LDT可以有多个,GDT只有一个

;流程:
;1.用户程序的读取
;2.为用户程序创建TCB任务控制块,创建LDT
;3.为用户程序建立描述符,并存放在LDT中
;4.为用户程序建立特权栈,特权栈的描述符存放在LDT中,特权栈的基本信息填充在TCB中
;5.为用户程序匹配符号表,并把门调用选择子填充到用户地址表中
;6.LDT界限确认(也就是为用户程序创建完所有需要的描述符)完毕后,为LDT建立系统段描述符,存放在GDT中
;7.创建TSS 以表示一个任务,以及TSS描述符(存放在GDT中)
;8. lldt ldt段选择子, ltr TSS段选择子
;8.1 加载LDT到LDTR, 使LDT生效, 这样就可以访问用户段描述符了
;8.2 让TR指向当前任务(用户程序),但并没有开始调度此任务
;9.通过调用门的返回流程,特权栈的切换的方式, 从特权0转移到特权3


;-----------------------------------------------------------



;-------------------------------保留上个文件的旧东西------------------
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

;地址表每项占用10字节
SYMBOL_TABLE_ADDR_EACH_ITEM_BYTES EQU 10

;用户符号信息表每项占用12字节
USER_SYMBOL_TABLE_EACH_ITEM_BYTES EQU 12

;用户程序扇区号
USER_APP_SECTOR EQU 100 



;在MBR中创建的所有描述符DPL=0, 对应的选择子RPL=0
;MBR中定义
SEL_4G_DATA equ 0x18    ;数据段
SEL_STACK EQU 0x20      ;栈
SEL_0XB8000 EQU 0x10    ;显存
SEL_MBR EQU 0X08        ;MBR段


;内核代码段和数据段所有描述符的DPL=0,选择子RPL=0
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

    ;-------------新增为所有的符号地址表过程创建调用门描述符----------------
    ;   此处的调用门描述符加入到了GDT中
    push dword 3                        ;参数,为用户创建的特权3调用门描述符
    call SEL_FUNC:create_call_gated     ;创建调用门描述符
    ;---------------------------------





    ;加载用户程序;
    push USER_APP_SECTOR
    call SEL_FUNC:load_app

    ;显示加载完毕信息
    mov ebx,loaded_msg_done - loaded_msg    ;长度
    push ebx
    push ds
    push dword loaded_msg
    call SEL_FUNC:print


    
    ;保存栈顶, 用户程序回来后恢复
    mov [ds:stack_top], esp

    ;---------------------转移到用户程序的修改------------------------------

    ;在之前, 直接跳转到用户程序中执行, 是因为用户程序也是特权0(DPL=0)
    ;但现在用户所有的段描述符DPL=3.
    ;特权是无法从高往低转移的
    ;但可以模拟调用门的方式来 假装 当前特权0的代码段是从用户(CPL=3)的代码段转移过来的

    ;首先模拟用户程序是一个任务, 需要加载TSS,LTD. 
    ;这些信息都在TCB中, 当前第一个TCB在数据段中的tcb_header
    ;0x10:LDT 选择子
    ;0x18:TSS 选择子
    
    mov ebx,SEL_4G_DATA
    mov es,ebx
    mov ebx,[ds:tcb_header] ;TCB地址

    ;一旦加载完成, 此局部描述符表立马生效. 可访问LDT中的任何描述符了
    lldt [es:ebx + 0x10]    ;加载LDT段选择子. 对应LDTR寄存器

    ;加载TSS到TR, 确定任务
    ltr [es:ebx + 0x18]     ;加载tss    . 对应TR寄存器

    ; 手动切换到TSS中的特权栈0 , 从TCB中比较容易获取, 反正都是同一个
    ;0x22:特权0, 栈选择子
    ;0x24:特权0, 栈esp

    mov ax, [es:ebx + 0x22]    ;特权0 栈选择子
    mov ss, ax
    mov esp, [es:ebx + 0x24]    

    ;根据高权限到低权限的返回方式:
    ;特权0 的栈中需要  特权3的ss,  特权3的esp , [参数1,参数2] ,  特权3的cs ,  特权3的eip. 这里没参数
    ; 特权3的段选择子, 都在用户头部段中

    mov eax, [es:ebx + 0x44]    ;获取用户头部段选择子
    mov ds, eax                 ;切换到用户头部段去获取

    ;模拟特权级改变的远返回, 注意push的顺序
    push dword [ds:0x38]         ;用户ss
    push dword 0                 ;用户esp
    push dword [ds:0x08]        ;用户cs
    push dword [ds:0x04]        ;用户起始地址   , 用户入口点

    ;由于栈中的cs.rpl > 当前CPL, 因此是一个特权远转移(需要 pop eip pop cs pop esp pop ss)
    ;注意这个从高到低的特权级转移, 转移到用户的入口点,没有参数,如果转移到一个有参数的过程,必须加上参数
    retf                    



    
    




    


;----------------以前的----------------    
    ;获取头部段选择子.进行跳转
 ;   mov eax,[ds:user_header_selector]
 ;   mov es,eax
 ;   jmp far [es:0x04]  
;----------------

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


;创建并追加TCB到链表中
;返回: eax 当前TCB地址
create_tcb_and_append_to_tcblinklist:
    push ebp 
    mov ebp , esp

    call SEL_FUNC:create_tcb    ;返回eax为新的TCB起始地址

    ;追加
    push eax
    call SEL_FUNC:append_to_tcb_linklist    ;追加到链表


    mov esp,ebp
    pop ebp
    retf

;创建一块内存给TCB使用
;返回: eax , 可用地址
create_tcb:
    push ebp
    mov ebp,esp
    push es

    mov eax,SEL_4G_DATA
    mov es,eax

    mov eax, 0x48           ;为TCB分配0x48字节
    push eax                ;需要分配多少字节
    call SEL_FUNC:alloc_mem ;返回eax 为可用地址

    ;为新创建的TCB清空头部4个字节
    mov dword [es:eax],0

    pop es
    mov esp,ebp
    pop ebp
    retf

;追加到TCB链表中
;参数: TCB地址(4字节地址)
append_to_tcb_linklist:
    push ebp
    mov ebp,esp
    push esi
    push eax
    push ebx
    push ds
    push es

    mov esi,[ebp + 12]  ;可用地址
    mov eax,SEL_4G_DATA
    mov es,eax          ;es指向4G
    mov eax,SEL_DATA
    mov ds,eax          ;ds指向自己数据段

    ;获取链表首地址
    ;如果链表为空,直接把当前TCB赋值
    ;如果链表不为空,则找到最后一个TCB,修改其TCB头为新增的TCB地址
    mov eax,[ds:tcb_header]     
    or eax,eax          ;判断是否为空链表
    jnz .not_empty

    ;为空
    mov [ds:tcb_header],esi
    jmp .append_to_tcb_linklist_done

    ;不为空的情况
    .not_empty:
        mov ebx,eax         
        mov eax,[es:ebx]    ;获取4字节地址,查看是否为空,eax指向下一个地址
        or eax,eax
        jnz .not_empty      
        mov [es:ebx],esi    ;找到最后一个TCB控制块,在首4字节处赋值

    .append_to_tcb_linklist_done:

    pop es
    pop ds
    pop ebx
    pop eax
    pop esi
    mov esp,ebp
    pop ebp
    retf 4


;根据符号表创建特权3的所有调用门描述符,用于特权级之间的调用
;参数:调用门DPL
create_call_gated:
    push ebp
    mov ebp,esp
    push ds
    push ebx
    push ecx
    push edx
    push eax
    push esi

    ;指向自己的数据段,获取符号地址表中的数据来创建门描述符
    mov ebx,SEL_DATA    
    mov ds,ebx
    ;指向地址表
    mov ebx,symbol_table_addr_begin 
    ;地址表项数
    mov ecx, [ds:symbol_table_addr_len]

    ;调用门DPL
    mov esi,[ebp + 12]
    and esi,11B       ; 仅保证最后2位有效
    shl esi,13        ; 左移到描述符DPL的位置

    ;为地址表每项创建调用门描述符
    .begin_create_call_gated_loop:
        ;用于属性的构造
        xor edx,edx
        xor eax,eax

        ;为每个门描述符构造属性,高32位中的低16位
        ;P(1),DPL(此过程的参数),参数个数. 这3个是需要自己填充的. 参数个数在地址表中已经填写好

        mov ax,[ds:ebx+0x06]    ;获取地址表中的参数个数
        mov dx,100_0_1100_000_00000B 
        or dx,si                    ; P,DPL 填充完毕
        or dx,ax                    ; 属性合成完

        push word dx
        push dword [ds:ebx]     ;过程偏移
        push word [ds:ebx + 0x04]     ;段选择子
        call create_one_call_gated    ;创建一个调用门描述符, 返回edx:eax

        push edx
        push eax
        call SEL_FUNC:add_to_gdt    ;把门描述符加入GDT, 返回eax(ax有效位) 门描述符选择子

        mov [ds:ebx+0x08],ax        ;把调用门描述符选择子填充到 地址表中

        add ebx,SYMBOL_TABLE_ADDR_EACH_ITEM_BYTES
    loop .begin_create_call_gated_loop

    pop esi
    pop eax
    pop edx
    pop ecx
    pop ebx
    pop ds
    mov esp,ebp
    pop ebp
    retf 4

;根据参数条件创建一个调用门描述符
;参数: 目标段选择子(2字节), 目标过程偏移地址(4字节), 门描述符属性(2字节)
;栈中位置: 8                    10                  14
;返回: edx:eax   门描述符8字节
create_one_call_gated:
    push ebp
    mov ebp,esp
    push esi

    xor esi,esi

    mov edx,[ebp + 10]  ;偏移地址
    mov eax,edx
    and eax,0x0000ffff  ;保留低16位
    and edx,0xffff0000  ;保留高16位
    mov si,[ebp + 14]   ;门属性
    or dx,si            ;高32位合成完毕

    mov si,word [ebp + 8]   ;段选择子
    shl esi,16
    or eax,esi          ;低32位

    pop esi
    mov esp,ebp
    pop ebp

    ret 8

;加载一个程序
;参数:用户程序的起始扇区号
load_app:
    push ebp
    mov ebp,esp
    pushad
    push es
    push ds

    ;------------新增tcb 任务控制块,用于跟踪每个task-------------
    ;创建一个TCB 来管理此任务
    call SEL_FUNC:create_tcb_and_append_to_tcblinklist ;返回eax , 新增TCB的地址
    mov esi,eax
    ;----------------------------------

    mov eax,SEL_4G_DATA
    mov es,eax

    ;----------------------为每个任务(用户程序)创建一个专属的LDT------
    ;这里为LDT分配80字节的空间, 也就是每个用户程序最多10个段描述符
    push dword 80
    call SEL_FUNC:alloc_mem     ;返回eax,LDT的可用地址

    ;给TCB初始化 任务基本信息
    mov word [es:esi + 0x0A], 0xffff    ;初始LDT界限:0xffff,当前为空,实际大小(0xffff+1)=0字节
    mov [es:esi + 0x0c],eax             ;初始化LDT基址

    ;----------------------------


    ;首先读取一个扇区,获取用户程序的头部信息
    ;由于需要动态给用户程序分配内存地址,因此不再直接把首个扇区读到指定内存地址
    ;加载用户头部的缓冲区在 自己的data段 : user_header_buffer 定义了512字节
    mov eax,SEL_DATA
    mov ds,eax
    mov ebx,user_header_buffer

    push ds                 ;段选择子
    push ebx                ;偏移
    push dword [ebp + 12]  ;扇区号
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
    mov [es:esi+0x06],edi       ;保存到TCB中

    ;把用户程序读取到 eax为起始地址的内存空间中
    push SEL_4G_DATA            ;4g 空间    
    push eax                    ;用户程序起始地址
    push ecx                    ;扇区数量
    push dword [ebp + 12]        ;起始扇区号
    call SEL_FUNC:read_user_app ;读取整个用户程序

    ;读完用户程序,需要给程序的每个段创建描述符,才能让用户程序运行起来
    ;此处将修改,之前是把描述符全部放在GDT中,现在把所有的描述符放在LDT中
    ;------------------修改----------------

    ;用户程序的起始地址,LDT 都可以从TCB中获取
    push dword SEL_4G_DATA              ;段选择子
    push esi                            ;TCB地址
    call SEL_FUNC:create_user_ldt_and_stack

    ;------------------

    ;----------之前的----------------
    ;push SEL_4G_DATA        ;段选择子
    ;push edi                ;用户程序被加载的起始地址
   ; call SEL_FUNC:create_user_gdt   ;为用户程序创建描述符和栈空间
    ;------------------


    ;用户程序符号表处理
    ;之前把 偏移地址, 段选择子 填充到用户地址表中, 现在将把已创建的调用门选择子填充进去

    push dword SEL_4G_DATA      ;段选择子
    push esi                    ;TCB地址
    call SEL_FUNC:realloc_user_app_symbol_table


    ;为用户程序创建额外的栈,
    push dword SEL_4G_DATA  ;段选择子
    push esi                ;TCB地址
    push dword 3            ;为用户创建额外的栈(指定对应特权的CPL即可)
    call SEL_FUNC:create_extra_stack_for_cpl    

    ;至此,用户的段描述符,栈描述符, 特权栈描述符, 全部已经存放到LDT中
    ;接下来需要让CPU认识LDT,就需要把LDT存放在GDT中
    ;GDT全局唯一,LDT每个任务一个
    ;为LDT创建描述符
    call SEL_FUNC:create_LDT_descriptor

    ;到这里
    ;1.用户程序读取完毕
    ;2.TCB任务控制块创建完,LDT创建完
    ;3.为用户程序建立描述符,并存放在LDT中
    ;4.为用户程序建立特权栈,特权栈的描述符存放在LDT中,特权栈的基本信息填充在TCB中
    ;5.为用户程序匹配符号表,并把门调用选择子填充到用户地址表中
    ;6.LDT界限确认(也就是为用户程序创建完所有需要的描述符)完毕后,为LDT建立系统段描述符,存放在GDT中

    ;接下来需要创建TSS(任务状态段)
    call SEL_FUNC:create_tss

    pop ds
    pop es
    popad
    mov esp,ebp
    pop ebp
    retf 4

;创建TSS
;参数: TCB地址, 段选择子

create_tss:
    push ebp
    mov ebp,esp
    push ebx
    push es
    push eax
    push edx
    push edi

    mov ebx,[ebp + 16]  ;段选择子
    mov es,ebx
    mov ebx,[ebp + 12]  ;TCB地址

    ;为TSS分配内存空间.TSS需要104字节
    ;TCB中的位置 : 0x12:TSS界限,0x14:TSS基址,0x18:TSS 选择子

    push dword 104  ;104字节
    call SEL_FUNC:alloc_mem     ;返回eax
    mov [es:ebx + 0x14], eax    ;TSS基址 写入TCB
    mov word [es:ebx + 0x12], 103     ;tss界限 写入TCB
    mov edi,eax                 ;备份

    ;为TSS创建描述符,描述符只能存放在GDT中
    ;TSS基址,界限都有了,还缺属性,TSS描述符是系统段描述符(S=0),TYPE=1001(1011表示繁忙),这里设置DPL=0
    mov edx,0x00008900      ;DPL=0,只能由特权0去调度任务

    push eax                ;基址
    push dword 103          ;界限
    push edx                ;属性
    call SEL_FUNC:make_gd   ;返回edx:eax

    push edx
    push eax
    call SEL_FUNC:add_to_gdt    ;返回ax 段选择子

    ;ax 保存到TCB中
    mov [es:ebx + 0x18],ax
    
    
    ;为TSS初始化
    mov word [es:edi], 0     ;previous task, 前一个任务:0. 没有前一个任务
    mov byte [es:edi + 100],0   ;T位=0; debug 调试用

    ;把之前创建的特权栈给TSS赋值
    ;TCB中保存的特权栈 位置:
    ;0x22:特权0, 栈选择子
    ;0x24:特权0, 栈esp

    ;0x30:特权1 栈选择子
    ;0x32:特权1 栈esp

    ;0x3e:特权2 栈选择子
    ;0x40:特权2 栈esp

    ;特权0 赋值
    mov eax, [es:ebx + 0x24]   ;esp
    mov [es:edi + 4], eax
    mov ax,[es:ebx + 0x22]      ;段选择子
    mov [es:edi + 8],ax

    ;特权1
    mov eax,[es:ebx + 0x32]     ;esp
    mov [es:edi + 12],eax
    mov ax,[es:ebx + 0x30]     ;段选择子
    mov [es:edi + 16],ax

    ;特权2
    mov eax,[es:ebx + 0x40] ;esp
    mov [es:edi + 20],eax
    mov ax,[es:ebx + 0x3e]  ;段选择子
    mov [es:edi + 24],ax

    ;把LDT 赋值到TSS;  
    ;TCB 中: 0x10:LDT 选择子
    mov ax, [es:ebx + 0x10]
    mov [es:edi + 96],ax  

    ;TSS IO位图,直接填写TSS的界限 ;先无视此位
    mov word [es:edi+ 102] , 103

    pop edi
    pop edx
    pop eax
    pop es
    pop ebx
    mov esp,ebp
    pop ebp

    retf 8

;为LDT创建描述符,存放在GDT中
;参数: TCB地址, 段选择子
;栈中位置: 8     12
;返回: eax (ax有效位) , LDT的段选择子
create_LDT_descriptor:
    push ebp
    mov ebp , esp
    push es
    push ebx
    push edx
    push eax
    push ecx

    mov ebx,[ebp + 12]  ;段选择子
    mov es,ebx
    mov ebx , [ebp + 8] ;TCB地址

    ;TCB中有LDT的基址,界限
    mov edx,[es:ebx + 0x0c] ;LDT基址
    movzx eax, word [es:ebx + 0x0a] ;界限
    ;LDT的属性:D=1, P=1,S=0,TYPE=0010,DPL=0. 只能给特权0访问
    mov ecx,0x00008200

    push edx        ;段基址
    push eax        ;段界限
    push ecx        ;段属性
    call SEL_FUNC:make_gd       ;返回edx:eax

    push edx
    push eax
    call SEL_FUNC:add_to_gdt    ;加入到GDT中, 返回LDT段选择子

    ;填充TCB中的LDT选择子
    mov [es:ebx+0x10],ax        ;设置LDT段选择子

    pop ecx
    pop eax
    pop edx
    pop ebx
    pop es
    mov esp,ebp
    pop ebp

    ret 8


; 为用户程序创建额外的栈
; 根据CPL来创建额外的栈, 例如用户CPL=3, 则需要额外创建特权为 :0,1,2 栈; CPL=1,则创建特权0的栈
;参数: 特权级别, TCB地址, TCB段选择子
;栈中位置: 12       16      20
create_extra_stack_for_cpl:
    push ebp
    mov ebp,esp
    pushad
    push es

    mov ecx,[ebp + 20]  ;段选择子
    mov es,ecx
    mov ebx,[ebp + 16]      ;TCB
    mov ecx,[ebp + 12]      ;特权级别,也是需要循环的次数

    ;检查特权级别是否 > 3, < 1 则不做处理
    test ecx,3
    jg .create_extra_stack_for_cpl_done
    test ecx,1
    jl .create_extra_stack_for_cpl_done


    mov edi,0       ;计数器,也用作DPL
    ;每个栈的基础属性是:0x00c09600, G=1,B=1,P=1,S=1,TYPE=0110
    ;栈的DPL 可以根据 edi, 再左移13位  : or 0x00c09600 , ( edi << 13 )
    ;默认每个栈4k. 如需改变,可通过增加参数    
    ;TCB中每个栈信息需要14字节,起始地址0x1A
    ;0x1A:特权0 栈长度,以4K为单位; 通过这个数可以用 : 0xfffff - 此长度 => 栈段的界限
    ;0x1E:特权0, 栈基址
    ;0x22:特权0, 栈选择子
    ;0x24:特权0, 栈esp

    mov esi,0x1A        ;TCB中 特权0 栈的首个位置

    .begin_create_extra_stack:
        push 0x1000             ;固定每个栈4K
        call SEL_FUNC:alloc_mem ;返回eax

        add eax,0x1000          ;栈的基址需要加上0x1000字节数
        mov [es:ebx + esi + 4], eax   ;在TCB中设置栈基址

        ;为栈构造段属性. 还缺DPL才能合成
        mov edx,edi
        shl edx,13
        or edx,0x00c09600       ;合成属性

        ;为栈创建描述符
        push eax            ;段基址
        push 0xffffe        ;段界限
        push edx            ;段属性
        call SEL_FUNC:make_gd   ;返回edx:eax

        ;把描述符放在TCB的LDT中
        push es             ;段选择子
        push ebx            ;TCB地址
        push edx            ;描述符高32位
        push eax            ;描述符低32位
        call SEL_FUNC:add_to_ldt_with_tcb       ;返回ax 段选择子

        ;修改选择子RPL, 根据当前的DPL来修改
        or ax,di

        ;把选择子放在TCB中
        mov [es:ebx + esi + 8] , ax
        
        ;设置栈ESP
        mov dword [es:ebx + esi + 10],0

        ;设置栈的长度
        mov dword [es:ebx + esi], 1   ;固定每个栈4K长度

        inc edi                 ;加增计数器,也是DPL
        add esi,14              ;指向下一个栈区
    loop .begin_create_extra_stack

    .create_extra_stack_for_cpl_done:
    pop es
    popad
    mov esp,ebp
    pop ebp

    retf  12

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
;参数:用户信息表地址偏移,用户可用的段选择子,    原信息表偏移,  原信息表段选择子 
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
;参数:用户地址表起始地址, 用户信息表地址,4G段选择子
;栈中位置: 8                12              16             
;拿用户信息表的一条与当前可以导出的信息表全部项进行比较
symbol_table_item_compare_and_fill:
    push ebp
    mov ebp,esp
    pushad
    pushfd
    push es
    push ds

    mov eax,[ebp + 16]      ;段选择子
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
        push es           ;4g段选择子
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
    push es       ;4G选择子
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

    ret 12

;填充地址
;参数:用户地址表,用户信息表地址,用户可用的段选择子(4G), 原信息表地址, 原段选择子
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

    ;可导出的地址表结构:
    ;dd : 偏移           ;0x00
    ;dw : 段选择子        ;0x04      -> 原来将偏移地址和段选择子填充到用户地址表中
    ;dw : 参数个数        ;0x06
    ;dw : 调用门选择子    ;0x08      ->现在修改成将门选择子 填充进用户地址表中

    mov ebx,[ds:esi + 8]        ;内核数据段的地址表项,此偏移地址存放着偏移地址,段选择子

    ;根据用户信息表项内的索引,确定用户地址表的位置,然后进行填充调用门选择子
    mov ecx,[es:edi + 8]        ;用户信息表项的索引
    shl ecx,3                   ;用户地址表每一项占用8字节(偏移,调用门段选择子)

    xor eax,eax
    mov ax,[ds:ebx + 8]         ;调用门的选择子
    ;调用门的RPL修改成3
    or ax,11B
    ;填充到用户地址表中
    mov dword [es:edx + ecx + 4], eax

    ;偏移地址填充0即可
    mov dword [es:edx + ecx],0

  ;  mov eax,[ds:ebx]            ;获取过程偏移地址
  ;  mov [es:edx + ecx],eax      ;在用户地址表中存放偏移地址

  ;  movzx eax, word [ds:ebx + 4]       ;过程的段选择子, 内核定义的地址表中段选择子是2个字节
  ;  mov [es:edx + ecx + 4], eax  ;在用户地址表中存放段选择子

    pop ds
    pop es
    popad
    mov esp,ebp
    pop ebp

    ret 20

;用户符号表处理
;参数: TCB地址,4g段选择子
realloc_user_app_symbol_table:
    push ebp
    mov ebp,esp
    pushad
    push es

    mov ebx,[ebp + 16]  ;段选择子
    mov es,ebx
    mov eax,[ebp + 12]  ;TCB地址
    mov ebx,[es:eax + 0x06] ;用户程序起始地址
    

    ;比较过程:
    ;拿用户程序的符号信息表与自己数据段中的符号信息表中的每一项比较
    ;如果匹配,则把自己数据段中的符号地址表(偏移,段选择子)填充到用户的符号地址表中

    ;用户符号信息表起始位置 0x3c
    mov ecx,[es:ebx + 0x3c]

    mov esi,[es:ebx + 0x40] ;   用户符号信息表首项地址

    mov edi,[es:ebx + 0x44] ;   用户符号地址表起始地址

    add esi,ebx             ;加上用户起始地址偏移
    add edi,ebx

    .compare_start:
        push es             ;段选择子
        push esi            ;用户符号信息表首项地址
        push edi            ;用户符号地址表起始地址
        call symbol_table_item_compare_and_fill
        add esi,USER_SYMBOL_TABLE_EACH_ITEM_BYTES   ;指向下一个符号信息表内的起始地址
    loop .compare_start
    
    
    pop es
    popad
    mov esp,ebp
    pop ebp

    retf 8

;为用户创建描述符,把描述符放入ldt中
;参数: TCB地址， 段选择子
create_user_ldt_and_stack:
    push ebp
    mov ebp,esp
    pushad
    push es
 
    mov ebx,[ebp + 16]  ;段选择子
    mov es,ebx              ;指向4G
    mov esi,[ebp + 12]  ;TCB地址

    mov ebx,[es:esi + 0x06] ;用户程序起始地址
    mov ecx,[es:ebx + 0x0c] ;用户程序的重定位表项数
    mov edi,0x10            ;用户程序头部重定位表起始地址

    ;处理重定位表
    .process_realloc_table:
        mov eax,[es:ebx + edi + 4]  ;段基址
        add eax,ebx                 ;实际段基址

        push eax
        push dword [es:ebx + edi]         ;段界限
        ;当前的段属性是自己写在用户程序中的. 无论用户DPL是什么,在这里强制DPL=3
        ; 3左移13位 = 0x6000
        mov eax, [es:ebx + edi + 8]     ;段属性
        or eax,0x6000                   ;强制DPL=3
        push eax
        call SEL_FUNC:make_gd       ;返回edx:eax    

        push SEL_4G_DATA        ;4G选择子
        push esi                ;TCB基址
        push edx                ;描述符高32位
        push eax                ;低32位
        call SEL_FUNC:add_to_ldt_with_tcb   ;返回eax,ax:段选择子

        ;段选择子写到用户程序重定位表中的段基址处
        or eax,11B  ;修改RPL=3
        ;写回用户头部
        mov [es:ebx+edi + 4] , eax      

        add edi,USER_SYMBOL_TABLE_EACH_ITEM_BYTES   ;指向下一项
    loop .process_realloc_table

    ;替换入口点的代码段基址
    mov eax,[es:ebx + 0x20] ;代码段选择子
    mov [es:ebx+0x08],eax

    ;把头部段选择子保存到TCB
    mov eax, [es:ebx+0x14]  ;头部段选择子
    mov [es:esi + 0x44],eax

    ;创建栈
    push es         ;段选择子
    push esi        ;TCB地址
    push dword 3          ;栈的DPL
    push dword 1          ;放入LDT
    call SEL_FUNC:create_stack_with_param



    pop es
    popad
    mov esp,ebp
    pop ebp

    retf 8

;创建stack,之前的create_stack直接把描述符存放在GDT中.因此重写一个,根据参数来决定stack的位置
;由于用户程序只指定以4K单位的栈,因此栈属性只涉及到DPL
;参数:栈描述符加入GDT还是LDT(0:GDT,1:LDT),栈DPL,TCB地址,TCB所属段选择子
;栈中位置: 12                             16    20     24
create_stack_with_param:
    push ebp 
    mov ebp,esp
    pushad
    push es

    mov ebx,[ebp + 24]  ;段选择子
    mov es,ebx
    mov ebx,[ebp + 20]  ;TCB地址

    mov edi,[es:ebx + 0x06 ]    ;用户程序起始地址
    mov eax,[es:edi + 0x34 ]    ;用户程序定义的栈大小(以4K为单位)
    mov ecx,0xfffff             ;栈界限最大值
    sub ecx,eax                 ;实际栈界限, 实际栈的最小偏移

    ;确定栈的属性,默认属性 : G=1,B=1,P=1,S=1,TYPE=0110, 只剩DPL,需要参数来决定
    ;DPL在位13-14
    mov edx, 0x00c09600     ;栈的默认属性,DPL=0
    mov esi,[ebp + 16]      ;指定的DPL
    shl esi,13
    or edx,esi              ;栈属性合成
    
    
    ;为栈分配内存空间
    shl eax,12      ;以4K为单位: 乘以4096; 实际字节数
    mov esi,eax     ;备份栈的字节数,后续需要加上
    push eax
    call SEL_FUNC:alloc_mem ;返回eax: 地址
    add eax,esi         ;栈基址

    
    ;为栈创建描述符
    push eax            ;段基址
    push ecx            ;段界限
    push edx            ;段属性
    call SEL_FUNC:make_gd       ;返回edx:eax

    mov ecx,[ebp + 12]      ;加入GDT,还是LDT
    or ecx,ecx  
    jnz .store_in_ldt
        ;加入GDT

        push edx
        push eax
        call SEL_FUNC:add_to_gdt    ;增加到GDT中,返回eax 段选择子

    jmp .create_stack_with_param_done
    .store_in_ldt:
        ;加入LDT
        push es                 ;4G选择子
        push ebx                ;TCB基址
        push edx                ;描述符高32位
        push eax                ;低32位
        call SEL_FUNC:add_to_ldt_with_tcb   ;返回eax,ax:段选择子

    .create_stack_with_param_done:
        ;修改段选择子的RPL=3
        or eax,11B
        ;把段选择子写回用户程序
        mov [es:edi + 0x38], eax

    pop es
    popad
    mov esp,ebp
    pop ebp
    retf  16

;把描述符加入到TCB的LDT中
;参数:描述符低32位,高32位, TCB基址, 段选择子(特指4G,除非既能访问TCB,也能访问LDT)
;栈中位置: 12       16      20      24
;返回:eax (ax有效位) , 段选择子
add_to_ldt_with_tcb:
    push ebp
    mov ebp,esp
    push es
    push edi
    push ebx
    push ecx
    push edx
    

    mov edi,[ebp + 24]  ; 段选择子
    mov es,edi
    mov edi,[ebp + 20]  ; TCB地址

    xor ecx,ecx
    mov ebx,[es:edi + 0x0c] ;LDT基址
    mov cx,word [es:edi + 0x0a] ;LDT界限
    mov edx,ecx              ;备份界限
    inc cx                  ;界限+1为下一个描述符可存放的位置
    add ebx,ecx             

    ;在TCB中的LDT中存放描述符
    mov ecx,[ebp + 12]  ; 低32位
    mov [es:ebx], ecx
    mov ecx, [ebp + 16] ;高32位
    mov [es:ebx + 4],ecx

    ;增加LDT的界限( 界限:2字节)
    add dx,8
    mov word [es:edi+0x0a],dx

    ;计算段选择子, 界限/8
    shr dx,3        ; 除8
    shl dx,3        ;左移3位
    ;在LDT中,TI位=1
    or dx,100B
    mov eax,edx


    pop edx
    pop ecx
    pop ebx
    pop edi
    pop es
    mov esp,ebp
    pop ebp

    retf 16


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

;根据:段基址,段界限,段属性创建一个描述符, 此过程改个名字比较好
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
    mov eax,[ebp + 8]   ;用户cs
    arpl cx,ax          ;修改RPL, 如果 数据段RPL < 用户cs的RPL 则修改成用户cs的RPL
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
        mov [es:print_pos],di
    

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

    ;tcb 链表
    tcb_header dd 0

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

    ;地址表长度
    symbol_table_addr_len dd (symbol_table_addr_end-symbol_table_addr_begin)/SYMBOL_TABLE_ADDR_EACH_ITEM_BYTES

    ;地址表
    symbol_table_addr_begin:
        print_addr  dd  print           ;偏移
                    dw  SEL_FUNC        ;段选择子
                    dw  3               ;参数个数
                    dw  0               ;待填充的门描述符选择子

        read_sector_addr dd read_sector
                         dw SEL_FUNC
                         dw 3           ;3个参数
                         dw  0               ;待填充的门描述符选择子

        make_gd_addr    dd make_gd
                        dw SEL_FUNC
                        dw 3            
                        dw  0               ;待填充的门描述符选择子

        exit_addr   dd  exit
                    dw SEL_FUNC
                    dw 0
                    dw  0               ;待填充的门描述符选择子

        
        compare_string_addr dd compare_string
                            dw SEL_FUNC
                            dw 5
                            dw  0               ;待填充的门描述符选择子
    symbol_table_addr_end:
    
data_end:

section tail
tail_end:
