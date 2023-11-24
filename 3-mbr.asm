;MBR本身占用512字节,起始地址0x7c00
;GDT的位置:0x7c00+0x200(512) = 0x7e00
;GDT的界限:2的16次方:2^16=64k=0x10000
;因此启动程序的位置放在: 0x7e00+0x10000 = 0x17e00
;启动程序所在的逻辑扇区固定在0x01

;GDT界限:2^16, 每个段描述符8个字节,最多可容纳8192个段描述符
;每当加载一个段描述符伪指令: mov es,10_000 ; 
;就会根据提供索引*8+GDT基地址 去获取此地址的段描述符,如果地址超出了(GDT基地址+GDT界限)则非法

;之前已经说过段界限的计算方式,这里再说明一下
;向上的段界限:指的是最大偏移 , 向下的段界限:特指<栈>, 是最小偏移
;段界限是一个数量单位,需要根据G位来计算实际的段界限,G:0 以字节为单位, G:1 以4k为单位
;拿下面的显存段描述符来说明:界限:0xffff,G=0. 段界限: (0xffff+1)*1-1,最终的段界限:段基地址+段界限:0xb8000 + (0xffff+1)*1-1
;下面栈段,段基址:0x7c00,段界限:0xffffe,G=1. 段界限:(0xffffe+1)*4096-1+1, 最后需要加上段基址:0x7c00+( (0xffffe+1)*4096-1+1 );

;section.段名.start 是从文件首(位置0)开始计算的实际物理段地址,相当于从内存地址0开始的物理段地址
;在实模式中,有20位的地址空间
;   1.段地址(section.段名.start)需要4个字节来存放,低20位有效位,假设段地址:0x1000
;   2.如果要计算逻辑段地址,则需要加上程序起始地址, 假设程序起始地址:0x10000
;       1.起始地址:0x10000 低2字节 + 段地址 低2字节 : 0x0000 + 0x1000 = 0x1000
;       2.起始地址:0x10000 高2字节 + 段地址 高2字节 : 0x0001 + 0x0000 = 0x0001, 此加法使用adc,别忘记进位
;       3.mov ax,0x1000, mov dx,0x0001
;       3.逻辑段地址 / 16, 因此低2字节: shr ax,4 = 0x100
;       5.高2字节中只有低4位是有效位(共20位), or ax,dx => 0x1100

;在32位保护模式中,有32位地址空间.物理段地址需要4字节存放
;保护模式中不需要计算逻辑段地址,而是要创建一个描述符
;描述符的基地址: section.段名.start(内存地址为0开始的物理地址) + 程序起始地址: section.段名.start+CORE_BASE_ADDR;
;段界限:可以在每个段的结尾增加一个标号来计算每个段的长度, 根据段长度-1 => 界限
;段属性:根据每个段是什么类型,自己在头部给出
;根据上述3个属性可以合成一个描述符

MBR_START_ADDR equ 0x7c00   ;MBR起始地址
CORE_BASE_ADDR equ 0x17e00  ;启动程序的起始地址
CORE_SECTOR equ 0x01        ;启动程序所在的扇区

SECTION mbr vstart=0
    ;实模式
    ;首先在GDT中创建一些需要用到的段描述符
    ;GDT_BASE 被定义成一个4字节的线性地址
    ;获取GDT的段地址,偏移地址
    mov ax,[cs:GDT_BASE + MBR_START_ADDR]        ;获取GDT低16位
    mov dx,[cs:GDT_BASE + MBR_START_ADDR + 2]    ;GDT高16位
    mov bx,16
    div bx

    ;ax:段地址, dx:偏移
    mov ds,ax       ;GDT段地址: 0x07e0
    mov bx,dx       ;偏移:0

    ;创建第一个描述符:哑元,0号描述符
    ;每个段描述符占用8个字节
    mov dword [ds:bx + 0x00],0
    mov dword [ds:bx + 0x04],0

    ;创建一个代码段描述符, 基地址:0x7c00, 界限:0x01ff , G=0 字节为粒度, D=1 使用32位操作数
    ;实际最大界限: 0x7c00 + ((0x01ff + 1)*1-1)
    ;此段地址0x7c00,与MBR起始地址一样, 主要是为了执行后面的[bits 32]编译的32位保护模式下的代码
    mov dword [ds:bx + 0x08] , 0x7c0001ff
    mov dword [ds:bx + 0x0c] , 0x00409800

    ;创建一个显存段描述符,用于输出
    ;段基地址:0xb8000,界限:0xffff,G=0, 64k
    ;实际最大界限: 0xb8000 + ((0xffff+1)*1-1)
    mov dword [ds:bx + 0x10], 0x8000ffff
    mov dword [ds:bx + 0x14], 0x0040920b

    ;创建一个指向4G内存的数据段,以便访问任何一个位置
    ;段基地址:0x0, 界限:0xfffff, G=1(以4K为单位)
    ;实际最大界限:0x0 + (0xfffff+1)*4k-1
    mov dword [ds:bx + 0x18],0x0000ffff
    mov dword [ds:bx + 0x1c],0x00cf9200

    ;创建栈段
    ;段基址: 0x7c00, 段界限:0xffffe,G=1 以4K为单位, B=1 32位操作数,即使用esp
    ;栈的段界限指的是最小偏移
    ;段界限:(0xffffe+1)*4096-1+1 = 0xFFFFF000
    ;实际最终段界限: 0x7c00 + ( (0xffffe+1)*4096-1+1 ) = 0x7c00 + 0xFFFFF000 = 0x6c00
    ;最小偏移:0x6c00 , 最高地址: 0x7c00 + 0xffff_ffff(esp) = 0x7bff
    ;每当 push ,pop, int, iret ,call 等需要操作栈的指令时,都会对越界进行检查
    ;例如: push eax
    ;需要检查: 最小偏移地址 <=  (esp - 4) 
    mov dword [ds:bx + 0x20],0x7c00fffe
    mov dword [ds:bx + 0x24],0x00cf9600

    ;设置GDT的界限
    mov word [cs:GDT_SIZE + MBR_START_ADDR], 39 ; 5个段描述符 : 5*8 -1
    ;设置GDTR, 共6个字节,低2字节GDT_SIZE, 高4字节GDT_BASE
    lgdt [cs:GDT_SIZE + MBR_START_ADDR] 

    ;打开A20地址线
    ;使用0x92端口,把此端口的位1置1
    in al,0x92
    or al,0x02
    out 0x92,al

    ;屏蔽中断
    cli

    ;开启CR0的PE位,PE位在位0
    mov eax,cr0
    or eax,1
    mov cr0 ,eax

    ;一旦开启PE位,当前在16位保护模式下运行了
    ;当前在16位保护模式中的D位还是0, 想进入32位保护模式,需要加载一个D=1的段描述符,因此需要使用jmp

    ;dword 用于修饰偏移地址:into_protect_mode, 使用4字节的偏移地址
    ;由于当前还是16位,因此会在机器码前加上前缀0x66, 运行时会使用32位操作数
    ;0x08是段选择子: 01_000B, 段选择子2个字节,高13位是索引,2^13=8192,对应GDT最大描述符个数
    ;段选择子传递给cs的过程,伪指令: mov cs, 0x08:
    ;   1.根据 ( 索引 * 8 ) + GDT_BASE 算出地址
    ;   2.查看此地址是否越界( GDT_BASE + GDT_SIZE)
    ;   3.未越界则把对应描述符加载到cs的高速缓冲区中
    ;以下面为例:
    ;   1. 0x08 = 01_000B, 索引为1
    ;   2. (1*8)+0x7e00 = 0x7e08, 不越界
    ;   3. 从0x7e08处获取8个字节加载到cs高速缓冲区中
    ;
    ;相当于伪指令: mov cs,0x08 ; mov eip, into_protect_mode
    ;最后由于段描述符被加载后D=1,因此使用eip, 即 eip = into_protect_mode

    jmp dword 0x08:into_protect_mode

;从这里开始将使用32位的操作数,由于当前的CS段描述符D=1
;bits 32 以32位编译代码, 默认情况是bits 16以16位编译
;如果当前没有bits 32的情况下, 而描述符的D位又为1, 即以32位方式执行16位的指令或许会发生错误
;16位的默认操作数是2字节,32位默认操作数为4字节. 即使有些编译好的指令看上去一样,但在运行时还是会发生错误
[bits 32]

    ;以32位操作数来执行指令
    into_protect_mode:

    ;设置栈段
    mov eax,0x20
    mov ss,eax
    xor esp,esp

    ;设置数据段,指向4G空间
    mov eax,0x18
    mov ds,eax

    ;读取启动程序第一个扇区,加载到CORE_BASE_ADDR处

    mov ebx,CORE_BASE_ADDR  ;写到ds:ebx
    mov edi,ebx         ;备份
    mov eax,CORE_SECTOR     ;指定起始扇区号

    call read_sector        ;读取首个扇区, 参数:eax , 写入到 ds:ebx

    mov eax,[ds:edi]        ;获取程序长度
    mov ecx,512
    xor edx,edx
    div ecx                 ;总字节数/512, 查看还要读取几个扇区

    or edx,edx              ;余数为0 ?
    jnz .check
    dec eax                 ;余数为0, -1首个已读的扇区

.check:
    or eax,eax              ;是否读完 ?
    jz  .read_done          ;读完则处理一步,否则继续读扇区

    mov ecx, eax            ;剩余扇区数
    mov eax, CORE_SECTOR    
.read_left:
    inc eax                 ;下一个扇区号
    call read_sector        ;读取扇区, ebx在read_sector中自增,因此不用管
    loop .read_left

;全部读完
.read_done:
    ;为所有的段创建段描述符
    ;程序的重定位表中已经把 段基址, 段界限, 段属性 全部提供
    ;程序被加载的位置:CORE_BASE_ADDR
    ;因此实际的段基址为: CORE_BASE_ADDR + 段基址

    ;当前ds:指向4G
    mov ecx,[ds:CORE_BASE_ADDR + 0x0c]         ;重定位表长度(有几项)
    mov edi,0x10                               ;重定位表起始地址

    ;保存ebp 原值
    push ebp
    mov ebp,0x28                               ;安装描述符的起始地址,实模式中最后一个地址:0x20

    ;处理重定位表
    ;这里的ebp:把描述符的地址当成段选择子来使用,只是凑巧,因为后3位(TI,DPL)都是0.
    .process_realloc_table:
        mov ebx,[ds:CORE_BASE_ADDR + edi]       ;段界限
        mov eax,[ds:CORE_BASE_ADDR + edi + 4]   ;段基址
        add eax,CORE_BASE_ADDR                  ;实际段基址
        mov esi,[ds:CORE_BASE_ADDR + edi + 8]   ;段属性
        
        ;合成描述符
        call make_gd    ;返回edx:eax 
        ;增加到GDT中
        mov esi,[ds:MBR_START_ADDR + GDT_BASE]  ;GDT起始位置
        mov [ds:esi + ebp],eax                  ;描述符低32位
        mov [ds:esi + ebp + 4],edx              ;描述符高32位

        ;把程序头部的段基址替换成段选择子
        mov [ds:CORE_BASE_ADDR + edi + 4],ebp

        add ebp,0x08                            ;下一个安装段描述符的位置
        add edi,0x0c                            ;下一个段项
    loop .process_realloc_table

    ;恢复ebp
    pop ebp

    ;修改入口点的段基址,替换成段选择子
    mov eax,[ds:CORE_BASE_ADDR + 0x20]
    mov [ds:CORE_BASE_ADDR + 0x08],eax

    ;传递显存段,栈段,4G数据段的段选择子
    mov dword [ds:CORE_BASE_ADDR + 0x40],0x18 ;4g数据段
    mov dword [ds:CORE_BASE_ADDR + 0x44],0x20 ;栈段
    mov dword [ds:CORE_BASE_ADDR + 0x48],0x10 ;显存段
    mov dword [ds:CORE_BASE_ADDR + 0x4c],0x08 ;MBR段


    ;修改GDT段界限
    mov word [ds:MBR_START_ADDR + GDT_SIZE], 71 ;9*8-1
    ;重载GDT,使其生效
    lgdt [ds:MBR_START_ADDR + GDT_SIZE]     

    ;跳转到内核程序中,此程序作废
    ;CORE_BASE_ADDR + 0x04 是目标程序的入口点, 存放了偏移地址,段选择子
    ;jmp far 用于段间转移, 将从目标地址处获取6个字节,低地址:偏移地址, 高地址:段选择子
    jmp far [ds:CORE_BASE_ADDR + 0x04]

    

;===================================================================================
;参数: eax 段基址, esi 属性 , ebx 段界限
;返回: edx:eax 描述符 edx 高32位, eax 低32位

;合成一个描述符
;段基址:32位, 段界限:20位
make_gd:
    mov edx,eax
    shl eax,16      ;保留低16位,用于合成低地址的32位描述符
    or ax,bx        ;低32位描述符组合完成

    and edx,0xffff0000  ;确保高16位基地址
    rol edx,8           ;;循环左移, 把高8位移动到低8位
    bswap edx           ;低8位和高8位交换. 至此高32位中的段基地址处理完成

    and ebx,0x000f0000  ;段界限的低16位已经在上面处理完成,只剩高4位是有效位
    or edx,ebx          ;段界限处理完成
    or edx,esi          ;合成属性

    ret

;===================================================================================
;读取一个扇区
;参数 : eax 逻辑扇区号 (为了减少传参)
;默认写入到 ds:ebx

;需要用到的端口号 0x1f2 ~ 0x1f7 , 0x1f0
;端口 0x1f2 = 设置扇区数量
;LBA28有28位 扇区号
;0x1f3 ~ 0x1f6 设置逻辑扇区号, 这些端口都是8位端口,因此只能传送一个字节来满足28位扇区号
;0x1f6端口只有低4位是端口号,高前3位111表示LBA模式,后1位表示主盘(0)从盘(1)
;0x1f7 用于读写命令,以及读取硬盘状态
;一般情况下先检测0x1f7的状态,检测第7位(是否繁忙)和第3位(准备交换数据)的状态
;即检测 : 1000_1000b  与 0x1f7读取回来的状态, 如果 1000_1000b and 状态 = 0000_1000b 则可以读写
;0x1f0用于读写数据, 这是一个16位端口,一次可以读取2个字节
read_sector:

    push eax
    push edx
    push ecx

    ;保存扇区号
    push eax
    
    ;设置扇区数量
    mov dx,0x1f2
    mov al,1
    out dx,al

    ;设置28位扇区号,端口:0x1f3 ~ 0x1f6
    pop eax
    inc dx  ;0x1f3
    out dx,al

    inc dx  ;0x1f4
    shr eax,8
    out dx,al

    inc dx  ;0x1f5
    shr eax,8
    out dx,al

    inc dx  ;0x1f6
    shr eax,8   ;只有低4位是逻辑扇区号有效位
    and al,0000_1111B   ;确保高4位0
    or al,0xe0          ;最低位:主盘,高3位:LBA模式 , 1110B
    out dx,al

    inc dx  ;0x1f7  
    mov al,0x20 ;读取命令
    out dx,al

    ;读取硬盘状态
    .read_disk_status:
        in al,dx        ;从0x1f7读取状态
        and al,1000_1000b   ;是否可以读取? 第3位如果是1则可以读取了
        cmp al,0000_1000b   ;检测第三位的状态,如果相等说明可以读取
        jnz .read_disk_status   ;不想等则继续等待

    ;开始读取扇区,从0x1f0读取数据,这是一个16位端口,一次读取2个字节
    mov dx,0x1f0
    mov ecx,256     ;一次读取2个字节, 256*2=512

    .begin_read:
        in ax,dx
        mov [ds:ebx],ax ;把读取到的2个字节复制到指定位置
        add ebx,2
        loop .begin_read


    pop ecx
    pop edx
    pop eax
    ret

GDT_SIZE dw 0           ;GDT界限
GDT_BASE dd 0x7e00      ;GDT的起始地址

times 510-($-$$) db 0
db 0x55,0xaa
