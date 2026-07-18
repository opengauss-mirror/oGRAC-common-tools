该项目为oGRAC性能测试使用的Benchmarksql工具的源码仓

基于原始的Benchmarksql的主要改动如下：
1. 新增配置参数nodeId，表示当前压测的节点ID，默认为0
2. 新增配置参数nodeCnt，表示集群中总共的节点数量，默认为1
3. 修改了jTPCC.java中terminalWarehouseID的赋值，修改为根据节点ID和节点数量使每个压测线程运行时使用的WarehouseID数据互不相同
4. 新增适配oGRAC的建表SQL：`tableCreates_par.sql`
5. 新增适配oGRAC的建索引SQL：`indexCreates_par.sql`
6. 新增适配oGRAC的压测配置示例：`ograc_run.og`

使用本仓的默认源码编译后的benchmarksql，进行两节点压测时，两个节点各自压测的数据冲突率接近为0
