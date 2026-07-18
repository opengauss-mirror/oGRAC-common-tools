#!/bin/bash

logfile="./outlog"
# 可选：如果是长期运行，建议保留一个历史报错日志，防止覆盖
error_log="./error_snapshot.log"

echo "开始运行基准测试监控..."

function auto_()
{
    expect <<-EOF
        spawn $*
        set timeout -1
        expect {
            "yes/no" { send "yes\n"; exp_continue }
            "denied" { exit 1; }
            "*assword:" { send "101demima@@\n"; exp_continue }
            "anger*\n*yes*" { send "yes\n"; exp_continue }
            "Pdb" { interact }
            "pass phrase for*:" { send "101demima@@\n"; exp_continue  }
            "passphrase" { send "101demima@@\n"; exp_continue  }
            "ograc_sys_pwd:" { send "Huawei@123\n"; exp_continue  }
        }
        #expect eof
EOF
}

function all_z_node_ssh_proc()
{
    ip=20.20.20.111
    echo "Executing on $ip"
    auto_ ssh root@$ip $*
}

function restart_two_nodes()
{
    chk_sql="alter system checkpoint"
    all_z_node_ssh_proc "su -s /bin/bash -l ograc -c 'ogsql / as sysdba -q -c \\\"$chk_sql\\\"'"
    all_z_node_ssh_proc "su -s /bin/bash -l ograc -c 'cms res -stop db -node 0 && cms res -stop db -node 1'"
    sleep 60
    all_z_node_ssh_proc "su -s /bin/bash -l ograc -c 'cms res -start dss -node 0 && cms res -start dss -node 1'"
    all_z_node_ssh_proc "su -s /bin/bash -l ograc -c 'cms res -start db -node 0 && cms res -start db -node 1'"
}

function run_test()
{
    > "$error_log"
    while true
    do
        > "$logfile" 
        echo "[$(date '+%F %T')] 启动 runBenchmark.sh ..."
        ./runBenchmark.sh props_111.ograc >> "$logfile"
        exit_code=$?
        
        # 修正 3: 优先检查脚本是否正常退出 (非0通常代表崩溃)
        # 如果脚本本身崩溃了，可能还没来得及写 "ERROR" 关键字，但也算失败
        if [ $exit_code -ne 0 ]; then
            echo "[$(date '+%F %T')] 检测到 runBenchmark.sh 非正常退出 (Exit Code: $exit_code)"
            cp "$logfile" "$error_log"
            echo "错误日志已保存至 $error_log"
            exit 1
        fi

        # 修正 4: 使用 grep -q (静默模式) 检查内容，避免变量引用问题
        # 只要找到一行 " ERROR " 就视为失败
        if grep -q " ERROR " "$logfile"; then
            echo "[$(date '+%F %T')] 检测到日志中包含 ' ERROR '，停止测试。"
            cp "$logfile" "$error_log"
            echo "错误日志已保存至 $error_log"
            # 可以在这里打印最后几行日志方便查看
            echo "--- 最后 10 行日志 ---"
            tail -n 10 "$logfile"
            exit 1
        fi
        
        echo "[$(date '+%F %T')] 本轮测试通过，准备下一轮..."
        echo "restart two nodes"
        sleep 5
        restart_two_nodes
    done
}

run_test
#restart_two_nodes
