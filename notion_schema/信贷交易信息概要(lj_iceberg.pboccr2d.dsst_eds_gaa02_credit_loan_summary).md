# 信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary)
page_id: 39c617cf-3593-80f5-a314-db63b44fe58e


| 字段解释 | 字段编码 | 字段名称 | 备注 | 数值类型 |
| 自增主键ID | id | 主键ID |  | long |
| 报告ID | id_unqf | 报告ID |  | varchar(32) |
| 客户ID | id_unqp | 客户ID |  | varchar(32) |
| 账户数合计 | account_num | 账户数合计 |  | short(8) |
| 业务类型数量 | business_type_num | 业务类型数量 |  | short(8) |
| 被追偿账余额合计 | recovery_balance | 被追偿账余额合计 |  | int |
| 被追偿业务类型数量 | recovery_business_type_num | 被追偿业务类型数量 |  | short(8) |
| 呆账账户数 | bad_debt_account_num | 呆账账户数 |  | short(8) |
| 呆账余额 | bad_debt_balance | 呆账余额 |  | int |
|  | ncl_org_num | 非循环贷账户汇总信息段-管理机构数 |  | int |
|  | ncl_account_num | 非循环贷账户汇总信息段-账户数 |  | short(8) |
|  | ncl_credit_amount | 非循环贷账户汇总信息段-授信总额 |  | int |
|  | ncl_balance | 非循环贷账户汇总信息段-余额 |  | int |
|  | ncl_avg6m_repayment | 非循环贷账户汇总信息段-最近六个月平均应还款 |  | int |
|  | cl_org_num | 循环贷账户汇总信息段-管理机构数 |  | short(8) |
|  | cl_account_num | 循环贷账户汇总信息段-账户数 |  | short(8) |
|  | cl_credit_amount | 循环贷账户汇总信息段-授信总额 |  | int |
|  | cl_balance | 循环贷账户汇总信息段-余额 |  | int |
| 账户数 | cl_avg6m_repayment | 循环贷账户汇总信息段-最近六个月平均应还款 |  | int |
|  | clsa_org_num | 循环额度下分账户汇总信息段-管理机构数 |  | short(8) |
|  | clsa_account_num | 循环额度下分账户汇总信息段-账户数 |  | short(8) |
|  | clsa_credit_amount | 循环额度下分账户汇总信息段-授信总额 |  | int |
|  | clsa_balance | 循环额度下分账户汇总信息段-余额 |  | int |
|  | clsa_avg6m_repayment | 循环额度下分账户汇总信息段-最近六个月平均应还款 |  | int |
|  | credit_account_num | 贷记卡账户汇总--账户数 |  | short(8) |
|  | credit_org_num | 贷记卡账户汇总--发卡机构数 |  | short(8) |
|  | credit_amount | 贷记卡账户汇总--授信总额 |  | int |
|  | credit_amount_sigle_max | 贷记卡账户汇总--单家机构最高授信额 |  | int |
|  | credit_amount_sigle_min | 贷记卡账户汇总--单家机构最低授信额 |  | int |
|  | credit_used_amount | 贷记卡账户汇总--已用额度/透支额度 |  | int |
|  | credit_used_amount_avg6m | 贷记卡账户汇总--最近6个月平均使用额度/透支额度 |  | int |
|  | scredit_account_num | 准贷记卡账户汇总--账户数 |  | short(8) |
|  | scredit_org_num | 准贷记卡账户汇总--发卡机构数 |  | short(8) |
|  | scredit_amount | 准贷记卡账户汇总--授信总额 |  | int |
|  | scredit_amount_sigle_max | 准贷记卡账户汇总--单家机构最高授信额 |  | int |
|  | scredit_amount_sigle_min | 准贷记卡账户汇总--单家机构最低授信额 |  | int |
|  | scredit_used_amount | 准贷记卡账户汇总--已用额度/透支额度 |  | int |
|  | scredit_used_amount_avg6m | 准贷记卡账户汇总--最近6个月平均使用额度/透支额度 |  | int |
| 相关还款责任个数 | duty_num_repayment | 相关还款责任个数 | 这个字段为什么会存放在这张表中？ | short(8) |
| 插入时间 | time_inst | 插入时间 |  | datetime |
可直接用于模型训练的特征共8项（含2个简单比率计算）：
信用卡使用率（credit_used_amount / credit_amount）
循环贷使用率（cl_balance / cl_credit_amount）
近6个月信用卡平均使用额度（credit_used_amount_avg6m）
发卡机构数量（credit_org_num）
非循环贷账户数（ncl_account_num）
呆账余额（bad_debt_balance）
被追偿余额（recovery_balance）
循环贷近6个月平均还款额（cl_avg6m_repayment，反映还款能力稳定性）