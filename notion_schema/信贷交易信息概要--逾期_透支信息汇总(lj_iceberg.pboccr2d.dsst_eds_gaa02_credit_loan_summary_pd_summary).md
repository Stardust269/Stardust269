# 信贷交易信息概要--逾期 透支信息汇总(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_pd_summary)
page_id: 39c617cf-3593-8099-8d4f-f5ca37fa065d


| 字段名称 | 备注 | 字段解释 | 字段编码 | 数值类型 |
| 主键ID |  | 自增主键ID | id | long |
| 报告ID |  | 报告ID | id_unqf | varchar(32) |
| 客户ID |  | 客户ID | id_unqp | varchar(32) |
| 业务类型 | 对应字典：overdue_collect_acc_type_code | 业务类型 | cre_tran_pro_type | varchar(16) |
| 账户数 |  | 账户数 | account_num | int |
| 逾期月份数 |  | 总共逾期的次数 | num_month | int |
| 单月最高逾期/透支金额 |  | 单月最高逾期/透支金额 | amt_pdtotal | long |
| 最长逾期/透支月数 |  | 首笔业务发放月份 | first_business_month | varchar(16) |
| 插入时间 |  | 插入时间 | time_inst | datetime |
可直接用于模型训练的特征共3项：
逾期月份数（num_month）→ 历史违约频率的核心指标；
单月最高逾期/透支金额（amt_pdtotal）→ 极端风险程度的量化依据；
信贷历史长度（动态计算）→ 修正逾期频率的上下文基准。