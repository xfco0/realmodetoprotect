;上一个core.asm 通过 call TSS选择子 来调度用户程序
;本程序 为内核添加一个TCB => 增加过程 init_kernel
        ;修改  create_kernel_tss 过程
        ;通过TCB位置:0x04的状态字段 来半自动切换任务
;添加一个switch_task 过程,用于切换任务
;switch_task 使用jmp指令执行新任务 
;   jmp指令会将当前任务的TSS描述符B=0,新任务TSS描述符B=1
;   保存当前上下文到TSS结构中
;   加载新任务的TSS结构到TR, 开始执行新任务


;TCB状态: 
;如果为1:是当前正在运行的任务
;2:任务结束,需要从链表中去除此任务
;0:可以运行的任务


;为每一个任务单独创建一个TCB,用于方便跟踪管理用户各种信息
;TCB包含了任务的所有所需的信息:
;TCB结构:  (总计0x58字节)
;0x00: 下一个TCB地址
;0x04:状态              ;0:不忙  1:忙   2:任务结束
;0x08:用户程序基址
;0x0c:LDT 界限 
;0x10:LDT基址
;0x14:LDT 选择子
;0x18:TSS界限
;0x1c:TSS基址 
;0x20:TSS 选择子
;0x24:用户头部段选择子

;0x28:特权0 栈基址
;0x2c:特权0 栈长度,字节为单位
;0x30:特权0 esp
;0x34:特权0 栈段选择子

;0x38:特权1 栈基址
;0x3c:特权1 栈长度
;0x40:特权1 esp
;0x44:特权1 栈段选择子

;0x48:特权2 栈基址
;0x4c:特权2 栈长度
;0x50:特权2 esp
;0x54:特权2 栈段选择子

;--------------------
;常量定义


;重定位表中的每一项段信息占用12字节
REALLOC_TABLE_EACH_ITEM_BYTES EQU 12

;符号信息表每项占用16字节
SYMBOL_TABLE_EACH_ITEM_BYTES equ 16

;地址表每项占用16字节
SYMBOL_TABLE_ADDR_EACH_ITEM_BYTES EQU 16

;用户符号信息表每项占用12字节
USER_SYMBOL_TABLE_EACH_ITEM_BYTES EQU 12

;用户程序扇区号
USER_APP_SECTOR EQU 100 

;分配内存的起始地址
ALLOC_MEM_BASE_ADDR EQU 0x100000



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

    ;创建调用门
    push dword 3                ;调用门DPL
    call SEL_FUNC:create_call_gate

    
    ;为内核创建TCB和TSS
    ;初始化内核使用的TCB和TSS
    ;并为内核TCB赋值状态字段 
    call SEL_FUNC:init_kernel


    push USER_APP_SECTOR    ;用户扇区号
    call SEL_FUNC:load_app  ;加载用户程序

  

    ;开始切换任务
    ;根据TCB中的状态来调度
    ;如果是1:当前正在运行的任务,2:结束的任务, 0:可以调度的任务
    ;调度任务使用: jmp TSS选择子
    ;jmp指令会将新任务的TSS描述符B=1,旧任务TSS描述符B=0
    ;同样的, 需要同步修改TCB中的状态
    ;在使用 jmp 指令时 内核代码被挂起, 上下文被保存到内核TSS结构中
    ;内核EIP指向 pop ds, 也就是等用户调用switch_task 后, 将执行这条指令
    call SEL_FUNC:switch_task
    

    ;--------------从用户任务切换回来----------------
    ;在用户任务保存自己的上下文在TSS后
    ;加载并切换到内核任务, TR=当前内核TSS选择子
    ;当前所有寄存器(上下文) 都将从内核TSS结构恢复
    ;此时cs=当前代码段,eip=hlt指令

    hlt

code_end:

section function vstart=0 align=16

;切换任务
switch_task:
    push ebp
    mov ebp,esp
    pushad
    push es
    push ds

    ;循环链表,找到下一个TCB状态为0的任务
    ;设置旧TCB状态为0, 设置新TCB状态为1
    ;使用jmp TSS选择子,进行任务切换

    mov eax,SEL_4G_DATA     ;4g
    mov es,eax

    mov eax,SEL_DATA        ;自己数据段
    mov ds,eax

    ;从当前正在运行的TCB往后找
    ;先判断是不是只有内核一个任务    
    mov eax,[ds:tcb_header]
    mov ecx,[es:eax]
    cmp ecx,0
    jz .switch_task_done        ;只有内核一个任务,就不切换
    
    mov ebx,[ds:tcb_curr]     
    .find_next_ready_task:
        mov ecx,[es:ebx]         ;首4个字节是下一个TCB地址
        or ecx,ecx               ;下一个为空
        jz .find_from_begining   ;从头开始
        cmp dword [es:ecx+0x04],0   
        jz .run_task             ;找到了
        mov ebx,ecx              ;找下一个
        jmp .find_next_ready_task
    

    ;从头开始找
    .find_from_begining:
        mov ebx,[ds:tcb_header]  
        cmp dword [es:ebx + 0x04],0
        cmovz ecx,ebx
        jnz .find_next_ready_task

    ;开始运行新任务
    .run_task:
        mov ebx,[ds:tcb_curr]   ;修改旧任务状态
        mov dword [es:ebx + 0x04],0
        mov [ds:tcb_curr],ecx   ;修改新任务地址
        mov dword [es:ecx + 0x04],1   ;修改新任务状态

        ;保存当前上下文到TR指向的TSS结构中
        ;把当前任务的TSS描述符B=0, 新任务的TSS描述符B=1
        ;加载新任务的TSS结构到TR中
        ;开始执行新任务
        jmp far [es:ecx + 0x1c ]    ;切换任务




    .switch_task_done:
    pop ds
    pop es
    popad
    mov esp,ebp
    pop ebp
    retf

;初始化内核:为内核创建TCB和TSS
init_kernel:
    push ebp
    mov ebp,esp
    push ds
    push es
    pushad

    mov eax, SEL_DATA
    mov ds,eax
    
    push dword 0x58
    call SEL_FUNC:create_tcb    ;返回eax, TCB地址
    mov edi,eax

    push eax                    ;加入TCB链表
    call SEL_FUNC:append_tcb_to_linklist


    ;为内核创建TSS
    ;这是一个空的TSS结构
    ;为了在切换到用户任务的时候,保存内核的所有寄存器到TSS结构中
    mov eax,SEL_4G_DATA
    mov es,eax

    push es                     ;TCB段选择子
    push edi                    ;TCB地址
    call SEL_FUNC:create_kernel_tss

    
    ;把 kernel_tss 加载任务寄存器TR 
    ;当前TR寄存器指向 kernel_tss描述符
    ;这个空的TSS结构只用于为当前正在运行的内核代码创建一个任务.
    ;以用来切换任务的时候能把当前状态保存到TSS结构
    ;ltr 只是加载并把描述符的B=1 (忙),并没有执行, 为了下面切换做准备
    
    ltr [es:edi + 0x20]         

    ;同时,为TCB状态字段赋值
    ;把内核TCB设置成:忙
    mov dword [es:edi + 0x04],1       ;1:忙 , 0: 不忙

    ;设置当前运行的TCB
    mov dword [ds:tcb_curr],edi

    popad
    pop es
    pop ds
    mov esp,ebp
    pop ebp
    retf

;加载程序
;参数: 用户程序扇区号
;栈中位置 : 12
load_app:
    push ebp
    mov ebp, esp
    push es
    push ds
    pushad

    mov eax,SEL_4G_DATA     ;4G空间
    mov es,eax

    ;创建一个TCB结构用于跟踪管理用户程序
    ;一个TCB结构需要0x58字节
    push dword 0x58
    call SEL_FUNC:create_tcb        ;返回eax,TCB地址
    mov edi, eax                    ;TCB地址保存一份
    push eax
    call SEL_FUNC:append_tcb_to_linklist    ;加入TCB链表

    ;为每一个任务创建一个LDT用于单独存放描述符
    ;每一个任务最多存放20个描述符
    push dword 0xA0                 ;字节数
    call SEL_FUNC:create_ldt
    mov [es:edi + 0x10], eax        ; TCB保存LDT基址
    mov dword [es:edi + 0x0c], 0xffff     ; 初始化LDT界限值, 当前共0字节,因此(0-1)=>最大界限


    ;开始读取用户程序
    push dword [ebp + 12]       ;用户起始扇区号
    call SEL_FUNC:read_user_app ;读取整个用户程序, 返回eax,用户起始地址
    mov [es:edi + 0x08], eax    ;保存基址

    ;为用户程序建立段描述符, 描述符存放在自身的LDT中
    push es                 ;访问TCB段选择子
    push edi                ;TCB地址
    push dword 3            ;为描述符建立哪种DPL
    call SEL_FUNC:create_app_descriptor

    ;为用户建立栈
    push es                     ;段选择子
    push edi                    ;TCB地址
    call SEL_FUNC:create_stack_for_user


    ;为用户建立TSS,用于任务切换
    ;TSS 描述符只能存放在GDT中
    push es                     ;段选择子
    push edi                    ;TCB地址
    push dword 0                ;TSS描述符DPL, 只能由特权0去调度
    call SEL_FUNC:create_min_tss    


    ;为用户建立额外的特权栈,用于特权转移(也就是通过调用门调用系统提供的过程)
    ;特权栈存放在TSS结构中
    ;此过程的参数 有些冗余了, 实际只需要传递 TCB地址, TCB段选择子即可,TCB中包含了TSS基址
    ;特权栈的描述符存放在LDT中

    push es                 ;TCB段选择子
    push edi                ;TCB地址
    push es                 ;访问TSS地址的段选择子
    push dword [es:edi + 0x1c]    ;TSS基址
    push dword 3            ;为用户程序创建特权栈
    call SEL_FUNC:create_privilege_stack

    ;到此, LDT的所有描述符(用户程序的段描述符,栈描述符, 特权栈描述符)全部建立完成,界限确定
    ;为LDT建立描述符, 存放在GDT中
    mov eax,edi             ;TCB地址
    add eax,0x0c            ;LDT界限的地址
    
    push es                 ;访问LDT的段选择子
    push eax                ;LDT界限的地址
    call SEL_FUNC:create_LDT_descriptor ; 返回 edx,eax 描述符

    push edx
    push eax 
    call SEL_FUNC:add_to_gdt        ;把LDT描述符加入GDT, 返回 ax 段选择子

    ;保存LDT段选择子到TCB中
    mov [es:edi + 0x14] , ax

    ;填充TSS的LDT字段
    mov ebx,[es:edi + 0x1c] ;tss基址
    mov [es:ebx + 96], ax


    ;为TSS寄存器的初始化
    push es                 ;TCB段选择子
    push edi                ;TCB地址
    call SEL_FUNC:init_TSS_regs


    ;加载局部描述符表 以使用头部段选择子
    lldt [es:edi + 0x14]

    ;为用户处理符号表
    push dword [es:edi+0x24]      ;用户头部段选择子
    call SEL_FUNC:realloc_user_app_symbol_table

    popad
    pop ds
    pop es
    mov esp,ebp
    pop ebp
    retf 4


;初始化TSS各寄存器的值
;参数: TCB地址, TCB段选择子
;栈中位置: 12       16
init_TSS_regs:
    push ebp
    mov ebp,esp
    push es
    push ebx
    push eax
    push esi
    push edi
    

    mov ebx,[ebp + 16]      ;段选择子
    mov es,ebx
    mov ebx,[ebp + 12]      ;TCB地址

    mov esi,[es:ebx + 0x08 ]    ;用户起始地址
    mov edi,[es:ebx + 0x1c]     ;TSS基址

    ;用户头部重定位表中的各个段选择子 来初始化 TSS 结构中的各寄存器
    ;TSS eip
    mov eax,[es:esi + 0x04]     ;入口点偏移
    mov [es:edi + 32] , eax

    ;TSS cs寄存器
    mov ax,[es:esi + 0x08]     ;入口点段选择子
    mov [es:edi + 76],ax

    ;TSS ds寄存器
    mov ax,[es:esi + 0x14]     ;用户头部段
    mov [es:edi + 84],ax

    ;TSS ss寄存器
    mov ax,[es:esi + 0x38]      ;栈段
    mov [es:edi + 80],ax

    mov word [es:edi + 92],0    ;GS
    mov word [es:edi + 88],0    ;FS
    mov word [es:edi + 72],0    ;ES
    mov dword [es:edi + 56],0   ;esp

    ;使用当前的 eflags
    pushfd
    pop eax
    mov [es:edi + 36],eax   

    pop edi
    pop esi
    pop eax
    pop ebx
    pop es
    mov esp,ebp
    pop ebp
    retf 8

;打印
;参数: 偏移, 数据段选择子, 字符串长度
;栈中位置: 12   16          20
print:
    push ebp
    mov ebp,esp
    pushad
    push es
    push ds

    mov ebx, [ebp + 16] ;段选择子
    mov eax, [ebp + 8]  ; 调用者代码段选择子
    arpl bx,ax          ;确认RPL
    mov es,ebx
    mov ebx , [ebp + 12]    ;偏移
    mov ecx, [ebp + 20]     ;长度

    mov eax,SEL_DATA
    mov ds,eax          ;自己数据段获取print_pos
    xor edi,edi
    mov di,[ds:print_pos]


    mov eax,SEL_0XB8000 ;显存段
    mov ds,eax

    xor eax,eax
    mov ah,0x07 ;字符属性

    .begin_print:
        mov al,[es:ebx]
        mov [ds:edi],ax
        inc ebx
        add di,2
    loop .begin_print

    ;更新位置
    mov eax,SEL_DATA
    mov ds,eax
    mov [ds:print_pos],di


    pop ds
    pop es
    popad
    mov esp,ebp
    pop ebp

    retf 12


;读取扇区
;参数: 读取到哪个偏移位置, 读取到哪个段选择子, 扇区号
;栈中位置: 12                   16          20
;返回 ebx 下一个可写入的地址

;端口: 0x1f2 用来设置扇区数量
;0x1f3 - 0x1f6  用来设置扇区号, 其中0x1f6只有低4位是最后的扇区号
;0x1f7 用来控制读/写, 反馈状态
;0x1f0 用来读取数据 
;28位扇区号,LBA模式
read_sector:
    push ebp
    mov ebp,esp
    push eax
    push ecx
    push edx
    push es


    mov eax,[ebp + 16] ;目标段选择子
    mov ebx,[ ebp + 8]  ;调用者CS
    arpl ax,bx          ;调整RPL
    mov es,eax
    mov ebx, [ebp + 12] ;偏移
    mov eax,[ebp + 20]  ;扇区号

    ;设置扇区数量
    push eax
    mov dx,0x1f2
    mov al,1
    out dx,al

    ;填充28位扇区号
    pop eax
    inc dx      ;0x1f3
    out dx,al

    shr eax,8
    inc dx      ;0x1f4
    out dx,al

    shr eax,8   
    inc dx      ;0x1f5
    out dx,al

    shr eax,8   ;剩余最后4位有效位
    inc dx      ;0x1f6
    and eax,0x0F    ;保留低4位
    or al,0xE0      ;1110_000B , LBA模式,从主盘读
    out dx,al

    ;设置读取状态
    inc dx      ;0x1f7
    mov al,0x20 ;读取
    out dx,al

    ;等待硬盘响应
    .read_disk_status:
        in al,dx
        and al,1000_1000b   ;检查是否可读
        cmp al,0000_1000b   ;如果第三位为1,则可读
        jnz .read_disk_status   ;否则继续检查

    
    ;从0x1f0中开始读取
    mov dx,0x1f0
    mov ecx,256     ;读取256次,每次读取2个字节

    .begin_read:
        in ax,dx
        mov [es:ebx],ax
        add ebx,2
    loop .begin_read



    pop es
    pop edx
    pop ecx
    pop eax
    mov esp,ebp
    pop ebp
    retf 12

;分配内存
;参数: 字节数
;返回: eax (内存地址)
alloc_mem:
    push ebp
    mov ebp, esp
    push es
    push ebx
    push ecx

    mov eax,SEL_DATA    ;自己数据段
    mov es,eax
    mov eax,[es:alloc_mem_addr] ;待返回的可用地址

    ;为下一个内存地址计算 : 以4对齐的地址 
    mov ebx,eax
    add ebx,[ebp + 12]  ;需要分配的字节数

    mov ecx,ebx         ;让其强制以4字节对齐
    and ecx,0xfffffffc
    add ecx,4           ;现在ECX是以4字节对齐的下一个可用内存地址了

    test ebx,3          ;测试ebx能否被4整除
    cmovnz ebx,ecx      ;若无法被4整除, 则相当于 : mov ebx, ecx

    ;填充下一个可用地址
    mov [es:alloc_mem_addr],ebx


    pop ecx
    pop ebx
    pop es
    mov esp,ebp
    pop ebp
    retf 4


;建立描述符
;参数: 段属性, 段界限, 段基址
;栈中位置: 12   16      20
;返回: edx,eax (高32位,低32位)
make_ds:
    push ebp
    mov ebp,esp
    push ecx

    ;处理低32位
    mov eax,[ebp + 20] ;基址
    mov edx,eax

    mov ecx,[ebp + 16]  ;界限

    shl eax,16
    and eax,0xffff0000
    or ax,cx            ;低32位合成完

    ;处理高32位
    and edx,0xffff0000
    rol edx,8           ;循环左移,高8位移动到低8位
    bswap edx           ;高低地址交换,原低8位移动到高8位, 基址完成
    
    and ecx,0x000F0000  ;界限仅高4位有效
    or edx,ecx          ;组合界限
    or edx,[ebp + 12]   ;组合属性
    

    pop ecx
    mov esp,ebp
    pop ebp
    retf 12

;增加描述符到GDT中
;参数: 描述符低32位, 描述符高32位
;栈中位置: 12           16
;返回: ax, 段选择子
add_to_gdt:
    push ebp
    mov ebp,esp
    push es
    push ebx
    push ds
    push ecx

    mov eax,SEL_DATA    ;自己数据段
    mov es,eax

    sgdt [es:GDT_SIZE]  ;存放当前GDT的界限和基址

    ;以GDT_BASE基址 , 根据界限+1, 可得下一个可存放位置
    xor ebx,ebx
    mov bx,[es:GDT_SIZE]    ;界限
    mov ecx,ebx             ;当前界限复制一份
    inc bx
    mov eax,[es:GDT_BASE]   ;GDT基址
    add ebx,eax

    ;存放在GDT中
    mov eax,SEL_4G_DATA
    mov ds,eax          ;指向4G

    mov eax,[ebp + 12]  ;低32位
    mov [ds:ebx],eax
    mov eax,[ebp + 16]  ;高32位
    mov [ds:ebx + 4],eax 

    ;增加界限
    add cx,8
    mov word [es:GDT_SIZE] , cx

    ;重新加载到GDTR中, 使之生效
    lgdt [es:GDT_SIZE]      

    ;计算段选择子, 使用 界限 / 8 可得到索引
    shr ecx,3      

    ;RPL 默认 : 0
    shl ecx,3
    xchg eax,ecx


    pop ecx
    pop ds
    pop ebx
    pop es
    mov esp,ebp
    pop ebp

    retf 8

;增加描述符到LDT中
;参数:描述符低32位, 描述符高32位, TCB地址,  访问TCB的段选择子
;栈中位置: 12           16        20            24
;返回: ax 段选择子(RPL 默认0 , TI=1 )
add_to_ldt:
    push ebp 
    mov ebp,esp
    push es
    push ebx
    push edi
    push esi
    push ecx
    push edx


    mov eax,[ebp + 24]  ;段选择子
    mov es,eax  
    mov ebx,[ebp + 20]  ;TCB地址

    mov edi, [es:ebx + 0x10]   ;LDT基址
    xor ecx,ecx
    mov cx,word [es:ebx + 0x0c]    ;LDT界限,仅低2字节有效
    mov edx,ecx
    inc cx             ;可存放描述符的首字节
    add edi,ecx        ;可存放描述符的地址

    ;存放描述符
    mov eax,[ebp + 12]  ;低32位
    mov [es:edi],eax
    mov eax,[ebp + 16]  ;高32位
    mov [es:edi + 4], eax

    ;增加ldt界限
    add dx,8
    mov [es:ebx + 0x0c],dx

    ;计算段选择子, 界限/8
    shr edx,3

    ;RPL默认=0, TI=1
    shl edx,3
    or edx,100B
    xchg edx,eax

    pop edx
    pop ecx
    pop esi
    pop edi
    pop ebx
    pop es
    mov esp,ebp
    pop ebp
    retf 16

;为特权3创建栈
;参数: TCB地址, TCB段选择子
;栈中位置: 12       16
create_stack_for_user:
    push ebp
    mov ebp,esp
    push es
    push ebx
    push edi
    push eax
    push edx

    mov ebx,[ebp + 16]       ;段选择子
    mov es,ebx
    mov ebx,[ebp + 12]       ;TCB地址

    mov edi,[es:ebx + 0x08]  ;用户起始地址
    mov eax,[es:edi + 0x34]  ;用户定义的栈大小

    push eax                ;栈大小
    push dword 3            ;为特权3创建的
    call SEL_FUNC:create_stack  ;创建栈,返回 edx,eax 描述符

    ;把栈段描述符加入LDT中
    push es                  ;TCB段选择子
    push ebx                 ;TCB地址
    push edx                 ;描述符高32位
    push eax                 ;低32位
    call SEL_FUNC:add_to_ldt    ;返回ax, 段选择子(TI=1,RPL=0)

    ;修改RPL=3
    or eax,11B
    mov [es:edi + 0x38],eax     ;写入用户程序头部的栈段选择子处

    pop edx
    pop eax
    pop edi
    pop ebx
    pop es
    mov esp,ebp
    pop ebp
    retf 8

;创建栈,以4K为单位的栈
;参数: 栈的DPL, 栈多大(以4K为单位)
;栈中位置: 12   16                  
;返回: edx,eax 栈段描述符
create_stack:
    push ebp
    mov ebp,esp
    push ebx
    push ecx
    push esi

    mov ebx,[ ebp + 12] ;DPL
    and ebx,0x03         ;保证仅最后2位有效

    ;测试DPL是否有效, > 3 或 < 0 无效
    cmp ebx,0x03
    jg .create_stack_done
    cmp ebx,0
    jl .create_stack_done

    mov ecx,[ebp + 16]  ;栈多大
    mov edx,1
    ;检查栈如果 <= 0 或 > 10 则只给默认4K的空间
    cmp ecx, 0
    cmovle ecx,edx
    cmp ecx,10
    cmovg ecx,edx

    ;为栈 申请内存 , 以及创建描述符
    
    mov edx,0xfffff         ;栈界限最大值
    sub edx,ecx             ;栈界限,最小偏移

    ;申请内存
    shl ecx,12              ; *4096, 得到实际字节数 ;此值以4K为单位
    push ecx
    call SEL_FUNC:alloc_mem ;返回eax
    add eax,ecx             ;栈基址, 栈空间在栈基址下面,因此需要加上字节数

    mov esi,0x00c09600      ;栈基础属性:G=1,B=1,P=1,S=1,TYPE=0110
    shl ebx,13              ;DPL在位13-14
    or esi,ebx              ;栈属性

    push eax                ;基址
    push edx                ;界限
    push esi                ;属性
    call SEL_FUNC:make_ds    ;创建描述符, 返回edx,eax

    .create_stack_done:
    pop esi
    pop ecx
    pop ebx
    mov esp,ebp
    pop ebp
    retf 8


;创建特权栈
;参数: 为谁创建特权级别的栈(3,2,1) , TSS地址, 访问TSS地址的段选择子, TCB地址,访问TCB的段选择子
;栈中位置: 12                       16          20                   24        28
create_privilege_stack:
    push ebp
    mov ebp, esp
    push es
    push ebx
    push ecx
    push eax
    push edx
    push edi
    push esi
    push ds


    mov ecx,[ebp + 12]      ; 以特权级别作为循环次数
    mov ebx,[ebp + 20]      ; TSS段选择子
    mov es,ebx
    mov ebx,[ebp + 16]      ;TSS地址
    add ebx,4               ;特权0 ,esp 首地址

    mov esi,[ebp + 28]      ;TCB段选择子
    mov ds,esi
    mov esi,[ebp + 24]      ;TCB地址
    add esi,0x28            ;指向首个栈
    ;TCB中也需要保存一份特权栈的信息
    ;0x28:特权0 栈基址
    ;0x2c:特权0 栈长度,字节为单位
    ;0x30:特权0 esp
    ;0x34:特权0 栈段选择子
    

    ;判断特权级别 参数是否正确, 如果 < 1 或 > 3则直接返回
    cmp ecx,3
    jg .create_privilege_stack_done
    cmp ecx,1
    jl .create_privilege_stack_done

    xor edi,edi     ;edi 作为栈属性的DPL , 0,1,2

    ;特权0栈的esp 从0x04开始,从特权0栈开始创建,最多额外创建3个栈(0,1,2)
    ;每个栈固定4K
    ;每个栈的基础属性是:0x00c09600, G=1,B=1,P=1,S=1,TYPE=0110
    ;栈的DPL 根据edi 每次左移13位 or 0x00c09600 => 栈属性
    ;段选择子的RPL, 根据DPL 来修改, 特权0=>RPL0, 特权1=>RPL1, 特权2=>RPL2
    ;栈的特权级检查 : CPL=RPL=DPL , 需要保持一致
    
    .begin_create_privilege_stack:

        push 0x1000             ;   4k大小
        call SEL_FUNC:alloc_mem ;返回 eax 可用地址
        add eax,0x1000          ;栈基址

        mov [ds:esi],eax        ;栈基址保存到TCB中
        mov dword [ds:esi + 4],0x1000 ;栈大小保存到TCB中

        mov edx,edi             ;处理DPL
        shl edx,13
        or edx,0x00c09600       ;合成栈属性

        push eax                ;基址
        push 0xffffe            ;界限
        push edx                ;属性
        call SEL_FUNC:make_ds   ;返回 edx , eax


        push ds                 ;访问TCB的段选择子
        push dword [ebp + 24]   ;TCB地址
        push edx                ;描述符高32位
        push eax                ;低32位
        call SEL_FUNC:add_to_ldt    ; ax 段选择子

        ;修改段选择子的RPL
        or ax,di

        ;设置到TSS块中
        mov dword [es:ebx],0            ;esp
        mov [es:ebx + 4], ax      ;栈选择子
        add ebx,8                 ;ebx指向下一个特权栈的esp
        
        ;把栈选择子保存到TCB中
        mov [ds:esi + 12], ax   ;TCB栈段选择子
        mov dword [ds:esi + 8], 0     ;TCB栈ESP
        add esi,16              ;指向TCB中下一个栈信息

        inc edi                   ;增加DPL
    loop .begin_create_privilege_stack



    .create_privilege_stack_done:
    pop ds
    pop esi
    pop edi
    pop edx
    pop eax
    pop ecx
    pop ebx
    pop es
    mov esp,ebp
    pop ebp

    retf 20


;为应用程序创建段描述符, 并存放到自己的LDT中
;参数: 应用程序的DPL, TCB地址, 访问TCB的段选择子
;栈中位置: 12           16          20
create_app_descriptor:
    push ebp
    mov ebp,esp
    pushad
    push es

    mov eax,[ebp + 20]      ;段选择子
    mov es,eax
    mov ebx,[ebp + 16]      ;TCB地址
    mov esi,[ebp + 12]      ;DPL,最后2位有效
    and esi,0x03    
    shl esi,13              ;左移13位;移动到描述符的DPL位置

    mov edi,[es:ebx + 0x08]   ;应用程序起始地址
    mov ecx,[es:edi + 0x0c]   ;应用程序重定位表项数

    mov ebx,0x10              ;重定位表的起始地址,这里是一个固定的值;
                              ;此处根据用户头部,随意更改

    .begin_create_descriptor:
        mov eax,[es:edi + ebx + 4]     ;段基址
        add eax,edi                    ;实际段基址

        push eax                       ;基址
        push dword [es:edi+ebx]        ;界限

        mov eax, [es:edi + ebx + 8]  ;获取属性
        ;不论原属性中的DPL是什么值,这里统一修改成参数中的DPL
        or eax,esi

        push eax                        ;属性
        call SEL_FUNC:make_ds           ;返回edx,eax

        ;把描述符存放到自己的LDT中
        push es                         ;访问TCB的段选择子
        push dword [ebp + 16]           ;TCB地址
        push edx                        ;描述符高32位
        push eax                        ;描述符低32位
        call SEL_FUNC:add_to_ldt        ;返回 ax, 段选择子(TI=1),RPL=0

        ;修改段选择子的RPL, 让其跟参数的DPL一致
        mov edx,[ebp + 12]  ;参数DPL
        and edx,0x03        ;仅低2位有效
        or eax,edx

        ;替换用户程序头部的 段基址
        mov [es:edi + ebx + 4] , eax

        add ebx,USER_SYMBOL_TABLE_EACH_ITEM_BYTES ;指向重定位表中的下一项
    loop .begin_create_descriptor

    ;修改头部入口点的段基址
    mov eax,[es:edi + 0x20]     ;此处是重定位表中代码段的位置
    mov [es:edi + 0x08], eax    ;修改入口点

    ;保存程序头部段选择子到TCB中
    mov eax,[es:edi + 0x14]     ;重定位表中的头部段选择子
    mov ebx,[ebp + 16]          ;TCB地址
    mov [es:ebx + 0x24],eax     ;保存头部段选择子


    pop es
    popad
    mov esp,ebp
    pop ebp
    retf 12

;创建一个LDT
;参数: 字节数
;返回:eax 
create_ldt:
    push ebp
    mov ebp,esp

    push dword [ebp + 12]   ;字节数
    call SEL_FUNC:alloc_mem

    mov esp,ebp
    pop ebp

    retf 4

;创建LDT描述符
;参数: 指向LDT界限的地址(地址+4 是LDT基址的地址) , 访问LDT的段选择子
;栈中位置: 12                                       16
;返回: edx,eax  描述符
create_LDT_descriptor:
    push ebp
    mov ebp,esp
    push es
    push ebx
    push edi
    push ecx

    mov eax,[ebp + 16]  ;段选择子
    mov es,eax
    mov ebx,[ebp + 12]  ;LDT界限的地址

    mov edi,[es:ebx + 4]    ;LDT 基址
    ;LDT的属性:D=0, P=1,S=0,TYPE=0010,DPL=0. 只能给特权0访问
    mov ecx,0x00008200
    movzx edx, word [es:ebx] ;界限

    ;建立描述符
    push edi        ;基址
    push edx        ;界限
    push ecx        ;属性
    call SEL_FUNC:make_ds   ;返回edx,eax

    pop ecx
    pop edi
    pop ebx
    pop es
    mov esp,ebp
    pop ebp

    retf 8

;为内核创建TSS
;参数:TCB地址,TCB段选择子
;栈中位置: 12   16
create_kernel_tss:
    push ebp
    mov ebp,esp
    push ds
    push es
    push eax
    push edx
    push ebx

    mov eax,SEL_4G_DATA     ;4G
    mov es,eax

    mov eax,[ebp + 16]  ;TCB段选择子
    mov ds,eax          

    mov ebx,[ebp + 12]  ;TCB地址

    ;TCB中的位置
    ;0x18:TSS界限
    ;0x1c:TSS基址 
    ;0x20:TSS 选择子

    push dword 104
    call SEL_FUNC:alloc_mem
    mov [ds:ebx + 0x1c], eax       ;tss基址
    mov dword [ds:ebx + 0x18], 103     ;TSS界限

    ;为内核的TSS初始化, 内核TSS不需要特权栈, 已经是特权0了
    mov word [es:eax]   ,0          ;前一个tss选择子 0
    mov dword [es:eax + 28],0       ;cr3
    mov word [es:eax + 96],0        ;LDT
    mov byte [es:eax + 100],0       ;T=0
    mov word [es:eax + 102],103     ;IO位图

    ;TSS描述符是系统段描述符(S=0),TYPE=1001(1011表示繁忙),P=1
    ;高32位中的描述符属性0x00008900, 由于当前是为特权0创建,因此DPL=0

    push eax                ;基址
    push dword 103          ;界限
    push dword 0x00008900   ;属性                    
    call SEL_FUNC:make_ds       ;返回edx,eax

    push edx
    push eax
    call SEL_FUNC:add_to_gdt    ;只能存放在GDT中

    ;保存TSS选择子
    mov word [ds:ebx + 0x20],ax
    
    pop ebx
    pop edx
    pop eax
    pop es
    pop ds
    mov esp,ebp
    pop ebp
    retf 8


;创建一个最小尺寸的TSS内存块
;参数: TSS描述符的DPL, TCB地址, TCB段选择子
;栈中位置: 12           16          20
create_min_tss:
    push ebp
    mov ebp,esp
    pushad
    push es
    push ds
    
    

    ;一个最小尺寸的TSS 需要104字节
    mov eax,104 

    ;申请内存块
    push eax
    call SEL_FUNC:alloc_mem ;返回eax
    mov ebx,eax             ;tss首地址

    ;为TSS初始化
    mov eax,SEL_4G_DATA
    mov es,eax
    mov word [es:ebx], 0        ; 前一个TSS段选择子
    mov byte [es:ebx + 100],0   ;T=0, debug位
    mov dword [es:ebx + 28],0   ;cr3
    mov word [es:ebx + 102],103 ; IO位图
    mov word [es:ebx + 96],0    ; LDT选择子
    mov dword [es:ebx + 56],0   ;esp

    ;为TCB中的TSS字段初始化
    mov eax, [ebp + 20]     ;TCB段选择子
    mov ds,eax
    mov edi, [ebp + 16]     ;TCB地址
    mov [ds:edi + 0x1c],ebx ;基址
    mov dword [ds:edi + 0x18], 103  ;界限


    ;为TSS创建描述符,并放入GDT中
    ;TSS基址已经有了, 界限:103 也有了
    ;基础属性 : TSS描述符是系统段描述符(S=0),TYPE=1001(1011表示繁忙),P=1

    mov eax,[ebp + 12]  ;描述符DPL
    and eax,0x03        ;只有低2位有效
    mov esi,eax         ;备份DPL
    shl eax,13          ;左移到DPL位置 ,DPL在位13-14

    ;TSS描述符的基本属性
    mov edx,0x00008900      ; 如果DPL=0, 只能由特权0 去调度任务
    or edx,eax              ; 设置DPL位

    ;创建描述符
    push ebx            ;基址
    push dword 103      ;界限
    push edx            ;属性
    call SEL_FUNC:make_ds   ;返回 edx,eax

    ;加入GDT
    push edx
    push eax
    call SEL_FUNC:add_to_gdt    ;返回 ax 段选择子
    
    ;RPL根据DPL来修改
    or ax,si

    ;保存到TCB的TSS选择子字段
    mov word [ds:edi + 0x20], ax
    
    pop ds
    pop es
    popad
    mov esp,ebp
    pop ebp
    retf 12


;读取用户程序
;参数: 用户程序扇区起始扇区号
;栈中位置: 12
;返回: eax 用户程序内存首地址
read_user_app:
    push ebp
    mov ebp,esp
    push ds    
    push edx
    push ecx
    push ebx


    mov eax,SEL_DATA    ;自己数据段
    mov ds,eax

    push dword [ebp + 12]     ;起始扇区号
    push ds             ;数据段
    push user_header_buffer ;偏移
    call SEL_FUNC:read_sector   ;读取一个扇区, 先把用户头部读进来分析需要多少个扇区

    ;计算扇区数
    mov eax,[ds:user_header_buffer] ;用户程序字节数
    xor edx,edx
    mov ecx,512
    div ecx

    mov ecx,eax                 ;备份扇区数
    inc ecx     
    or edx,edx                  ;有没有余数
    ;jz .alloc_mem_for_user      ;没有
    ;inc eax                     ;有余数
    cmovnz eax,ecx               ;有余数则+1扇区数
    

    ;为用户程序分配空间
    .alloc_mem_for_user:
    mov ecx,eax                 ;实际需要的扇区数
    shl eax,9                   ; *512字节 , 实际需要的字节数. 
    
    push eax                    ;为用户程序分配这些空间
    call SEL_FUNC:alloc_mem     ;返回eax , 首地址
    mov ebx,eax

    mov edx,[ebp + 12]          ;起始扇区号
    ;循环读取
    .begin_read_user_app:

        push edx            ;扇区号
        push SEL_4G_DATA    ;段选择子
        push ebx            ;偏移
        call SEL_FUNC:read_sector
        inc edx
    loop .begin_read_user_app


    pop ebx
    pop ecx
    pop edx    
    pop ds
    mov esp,ebp
    pop ebp
    retf 4

;创建TCB
;参数: 字节数
;返回 eax 地址
create_tcb:
    push ebp
    mov ebp,esp
    push es

    mov eax,SEL_4G_DATA
    mov es,eax

    push dword [ebp + 12]
    call SEL_FUNC:alloc_mem

    mov dword [es:eax],0    ;头部4字节清空
    mov dword [es:eax + 4], 0 ;状态清空

    pop es
    mov esp,ebp
    pop ebp

    retf 4


;把TCB加入链表
;参数:TCB地址
append_tcb_to_linklist:
    push ebp
    mov ebp,esp
    push ds
    push eax
    push ebx
    push es
    push ecx

    mov ebx,SEL_DATA    ;指向自己的数据段
    mov ds,ebx
    mov ebx,SEL_4G_DATA ;指向4G
    mov es,ebx

    mov eax,[ebp + 12]  ;TCB地址

    mov ebx,[ds:tcb_header] ;获取链表起始地址
    ;检查是不是空的, 如果不是循环到最后一个TCB
    or ebx,ebx              
    jnz .not_empty

    ;空的
    mov [ds:tcb_header],eax
    jmp .append_tcb_to_linklist_done

    ;不空,一直找下一个
    .not_empty:
        .find_next:
            mov ecx,ebx
            mov ebx,[es:ecx]
            or ebx,ebx
            jnz .find_next

        mov dword [es:ecx], eax     ;找到最后一个 填充TCB地址


    .append_tcb_to_linklist_done:
    pop ecx
    pop es
    pop ebx
    pop eax
    pop ds
    mov esp,ebp
    pop ebp

    retf 4

;比较字符串
;参数: 目标偏移, 目标段选择子, 原偏移, 原段选择子, 字符串长度
;栈中位置: 12       16          20      24          28
;返回:eax (1:相等,0:不相等)
compare_string:
    push ebp
    mov ebp,esp
    pushfd
    push ds
    push es
    push edi
    push esi
    push ecx
    push edx
    
    
    mov edi, [ebp + 16]     ;目标段
    mov edx, [ebp + 8]      ;cs
    arpl di,dx              ;如果di.RPL < cs.RPL 则修改成cs.RPL
    mov es,edi
    mov edi,[ebp + 12]      ;目标偏移

    mov esi,[ebp + 24]      ;原段
    arpl si,dx              ;判断RPL
    mov ds,esi
    mov esi,[ebp + 20]      ;原偏移

    mov ecx,[ebp + 28]      ;长度


    xor eax,eax
    mov edx,1

    cld
    repe cmpsb              ;一直比较直到最后一个字节也相等,标志Z=1
    cmovz eax,edx


    pop edx
    pop ecx
    pop esi
    pop edi
    pop es
    pop ds
    popfd
    mov esp,ebp
    pop ebp

    retf 20

;比较一项用户符号信息 与 一项自己公开的符号信息
;参数:用户符号信息项偏移地址, 用户段选择子,  原符号信息项偏移地址,原段选择子
;栈中位置: 8                  12                16                 20 
;返回: eax    (相等:1, 不相等:0)
compare_each_symbol_item:
    push ebp
    mov ebp,esp
    push ds
    push es
    push esi
    push edi

    mov esi,[ebp + 20]      ;原段选择子
    mov ds,esi
    mov esi,[ebp + 16]      ;原偏移

    mov edi, [ebp + 12]     ;用户段选择子
    mov es,edi
    mov edi,[ebp + 8]       ;用户偏移

    ;每一项的起始4字节都是字符串的长度. 首先比较字符串长度
    ;cmpsd会影响esi,edi 都+4, 因此先保存在栈中
    xor eax,eax
    push esi
    push edi
    cld                ;方向标志位
    cmpsd              ;比较4字节是否相等
    pop edi
    pop esi
    jnz .compare_each_symbol_item_done      ;长度不相等直接结束

    ;比较字符串
    push dword [es:edi]         ;字符串长度
    push ds                     ;原段
    push dword [ds:esi+4]       ;原字符串偏移
    push es                     ;目标段
    push dword [es:edi+4]       ;目标字符串偏移
    call SEL_FUNC:compare_string
    
    .compare_each_symbol_item_done:

    pop edi
    pop esi
    pop es
    pop ds

    mov esp,ebp
    pop ebp
    ret 16

;填充用户符号地址表
;参数:用户符号地址表地址,用户符号信息项地址,  用户段选择子, 原符号信息项地址,原段选择子
;栈中位置: 8                12                  16          20              24
fill_symbol_table_item:
    push ebp
    mov ebp, esp
    push ds
    push es
    push eax
    push ebx
    push esi
    push edi

    mov esi,[ebp + 24]  ;原段
    mov ds,esi
    mov esi,[ebp + 20]  ;原符号项

    mov edi,[ebp + 16]  ;用户段
    mov es,edi
    mov edi , [ebp + 12]       ;用户符号信息项

    mov ebx,[es:edi + 0x08]    ;用户过程索引号
    shl ebx,3                  ;索引 * 8 即是地址表中的需要填充的位置
    
    mov edi,[ebp + 8]          ;用户地址表
    add edi,ebx                 ;实际需要填充的位置

    mov esi,[ds:esi + 8]      ;指向对应的符号地址表项
    mov eax,[ds:esi + 8]      ;地址表中的门选择子

    ;为门选择子修改RPL
    or eax,11B

    mov dword [es:edi] , 0     ;用户地址表中的偏移地址,填充0即可
    mov [es:edi + 4],eax        ;填充门选择子


    pop edi
    pop esi
    pop ebx
    pop eax
    pop es
    pop ds
    mov esp,ebp
    pop ebp

    ret 20

;比较用户符号表的每一项,如果匹配则把门段选择子填充进去
;参数: 用户符号地址表地址 ,用户符号信息表项的地址, 用户头段选择子
;栈中位置: 8                12                      16
compare_each_symbol_table_item_and_fill:
    push ebp
    mov ebp,esp
    push ds
    push es
    push esi
    push edi
    push ecx
    push eax

    ;循环自己的符号表 与 用户信息表做比较

    mov esi,SEL_DATA    ;自己的数据段
    mov ds,esi

    mov esi,symbol_table_info_begin  ;指向自己符号信息表的首地址

    mov ecx, [ds:symbol_table_len]  ;自己符号表的长度

    mov edi,[ebp + 16]  ;用户段选择子
    mov es,edi
    mov edi,[ebp + 12]  ;用户符号信息表的一项地址


    .begin_compare_each_symbol:

        push ds             ;原段选择子
        push esi            ;原符号信息的一项地址
        push es             ;用户段选择子
        push edi            ;用户符号信息的一项地址
        call compare_each_symbol_item  

        or eax,eax          ;是否匹配, 1是匹配,0则继续下一条匹配
        jnz .begin_fill_addr    ;找到了

        add esi,SYMBOL_TABLE_EACH_ITEM_BYTES    ;指向自己的符号信息表的下一项
    loop .begin_compare_each_symbol
    
    ;到这里,把自己的符号信息表全部循环完都没找到,直接结束
    jmp .compare_each_symbol_table_item_and_fill_done

    ;开始填充门选择子
    .begin_fill_addr:

        push ds                 ;原段选择子
        push esi                ;原符号信息项地址
        push es                 ;用户段选择子
        push edi                ;用户符号信息项地址
        push dword [ebp + 8]    ;用户符号地址表地址
        call fill_symbol_table_item

    .compare_each_symbol_table_item_and_fill_done:

    pop eax
    pop ecx
    pop edi
    pop esi
    pop es
    pop ds
    mov esp,ebp
    pop ebp
    ret 12

;重定位用户符号表
;参数:  用户头部段选择子
;栈中位置:    12
realloc_user_app_symbol_table:
    push ebp
    mov ebp,esp
    push es
    push ebx
    push ecx
    push esi
    push edi

    mov ebx,[ebp + 12]  ;段
    mov es,ebx

    ;获取用户符号表长度
    mov ecx, [es:0x3c]    ;用户符号表长度

    mov esi,[es:0x40]     ;用户符号信息表 首地址

    mov edi,[es:0x44]     ;用户符号地址表 首地址

    ;循环; 每次拿出一条用户符号信息表中的项去比较
    .begin_realloc_user_app_symbol_table:
        push es
        push esi
        push edi
        call compare_each_symbol_table_item_and_fill
        add esi,USER_SYMBOL_TABLE_EACH_ITEM_BYTES   ;指向符号信息的下一项 
    loop .begin_realloc_user_app_symbol_table

    pop edi
    pop esi
    pop ecx
    pop ebx
    pop es
    mov esp,ebp
    pop ebp

    retf    4

;创建所有的调用门
;参数:调用门DPL
create_call_gate:
    push ebp
    mov ebp,esp
    push ds
    pushad

    ;为自己的符号地址表 填充调用门选择子
    ;地址表中, 段选择子和偏移地址已经有了. 还缺属性, 就能合成描述符
    ;调用门描述符的基础属性S=0,P=1,TYPE=1100  : 100_0_1100_000_00000B
    ;DPL通过参数传递, 参数个数 在符号地址表中已经给出

    mov ebx,symbol_table_addr_begin ;符号地址表首地址
    mov eax,SEL_DATA                ;指向自己的数据段
    mov ds,eax
    mov ecx,[ds:symbol_table_addr_len]  ;获取地址表长度

    mov esi,[ebp + 12]      ;调用门DPL, 仅低2位有效
    and esi,11B
    shl esi,13              ;左移13位, DPL在描述符中的位置

    .begin_create_all_gate:

        mov edx,100_0_1100_000_00000B   ;基础属性
        mov eax,[ds:ebx + 12]           ;获取 参数个数, 调用门的参数个数最多31个,这里为了方便使用4个字节
        and eax,0x1f                    ;最多31个参数, 0x1f = 11111B
        or edx,eax                      ;组合 -> 过程参数
        or edx,esi                      ;组合DPL

        push dword [ds:ebx + 4]         ;过程段选择子
        push dword [ds:ebx]             ;过程偏移地址
        push edx                        ;属性
        call SEL_FUNC:create_call_gate_descriptor   ;返回edx,eax

        ;加入到GDT中
        push edx
        push eax
        call SEL_FUNC:add_to_gdt        ;返回 ax 段选择子

        ;把门描述符的段选择子 填充到地址表中
        mov [ds:ebx + 0x08], eax

        ;指向下一个符号地址表项
        add ebx,SYMBOL_TABLE_ADDR_EACH_ITEM_BYTES
    loop .begin_create_all_gate

    popad
    pop ds
    mov esp,ebp
    pop ebp

    retf 4


;创建一个调用门描述符
;参数:   属性, 偏移, 段选择子
;栈中位置:12    16   20
;返回 edx,eax
create_call_gate_descriptor:
    push ebp
    mov ebp,esp
    push esi

    mov edx,[ebp + 16]  ;偏移
    mov eax,edx         

    and eax,0x0000ffff  ;保留低16位
    and edx,0xffff0000  ;保留高16位
    mov esi,[ebp + 12]  ;描述符属性
    and esi,0x0000ffff  ;低16位有效
    or edx,esi          ;组合高32位

    mov esi,[ebp + 20]  ;段选择子
    shl esi,16          ;左移到高16位
    or eax,esi          ;组合低32位 

    pop esi
    mov esp,ebp
    pop ebp
    retf 12


exit:
    retf

function_end:

section data vstart=0 align=16

    user_header_buffer times 512 db 0   ;用户头部缓冲区

    print_pos dw 0      ;打印位置

    alloc_mem_addr dd ALLOC_MEM_BASE_ADDR ;内存地址

    tcb_header dd   0     ;链表起始地址

    tcb_curr   dd   0     ;当前正在运行的任务

    GDT_SIZE dw 0   ;GDT界限
    GDT_BASE dd 0   ;GDT基址

    running_msg db 'kernel running'
    running_msg_end:

    ;符号信息表长度
    symbol_table_len   dd    (symbol_table_info_end-symbol_table_info_begin)/SYMBOL_TABLE_EACH_ITEM_BYTES

    ;符号信息表,用于匹配用户符号表
    symbol_table_info_begin:
        print_info      dd     (read_sector_string - print_string)     ;字符串长度
                        dd     print_string                            ;字符串偏移
                        dd     print_addr                              ;地址
                        dd     0                                       ;索引

        read_sector_info dd (exit_string - read_sector_string)
                         dd read_sector_string
                         dd read_sector_addr
                         dd 1

        exit_info       dd (compare_string_string - exit_string)
                        dd exit_string
                        dd exit_addr
                        dd 2

        compare_string_info dd  (switch_task_string - compare_string_string)
                            dd  compare_string_string
                            dd  compare_string_addr
                            dd 3

        switch_task_info  dd (symbol_table_string_end - switch_task_string)
                          dd switch_task_string
                          dd switch_task_addr
                          dd 4

    symbol_table_info_end:

    ;字符串表
    symbol_table_string_begin:
        print_string db 'print'
        read_sector_string db 'read_sector'
        exit_string db 'exit'
        compare_string_string db 'compare_string'
        switch_task_string db 'switch_task'
    symbol_table_string_end:


    ;地址表长度
    symbol_table_addr_len   dd   (symbol_table_addr_end-symbol_table_addr_begin)/SYMBOL_TABLE_ADDR_EACH_ITEM_BYTES

    ;符号地址表
    symbol_table_addr_begin:
        print_addr          dd print     ;偏移
                            dd SEL_FUNC  ;段选择子
                            dd 0         ;待填充的门选择子
                            dd 3         ;参数个数

        read_sector_addr    dd  read_sector     
                            dd  SEL_FUNC
                            dd  0
                            dd 3

        exit_addr           dd exit
                            dd SEL_FUNC
                            dd 0
                            dd 0

        compare_string_addr dd compare_string
                            dd SEL_FUNC
                            dd 0
                            dd 5

        switch_task_addr    dd switch_task
                            dd SEL_FUNC
                            dd 0
                            dd 0

    symbol_table_addr_end:
data_end:

section tail 
tail_end:
