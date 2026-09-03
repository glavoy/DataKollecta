Automatic Variables Migration Examples
Here are the XML configurations corresponding to your Visual Basic logic.

1. mrccode
VB Logic: Query mrccode from hh_info using HHID.

<question type="automatic" fieldname="mrccode">
  <calculation type="query">
    <sql>SELECT mrccode FROM hh_info WHERE hhid = @hhid</sql>
    <parameter name="@hhid" field="hhid" />
  </calculation>
</question>



2. region
VB Logic: Query region from hh_info using HHID.

<question type="automatic" fieldname="region">
  <calculation type="query">
    <sql>SELECT region FROM hh_info WHERE hhid = @hhid</sql>
    <parameter name="@hhid" field="hhid" />
  </calculation>
</question>


3. smcgiven
VB Logic: Query smcgiven from hh_info using HHID.

<question type="automatic" fieldname="smcgiven">
  <calculation type="query">
    <sql>SELECT smcgiven FROM hh_info WHERE hhid = @hhid</sql>
    <parameter name="@hhid" field="hhid" />
  </calculation>
</question>


4. feverortemp
VB Logic: Return "1" if fever = 1 OR temperature >= 38, else "0". Note: The case logic evaluates sequentially. If the first when matches, it returns. This effectively implements the OR logic.

<question type="automatic" fieldname="feverortemp">
  <calculation type="case">
    <!-- Condition 1: If fever is 1 -->
    <when field="fever" operator="=" value="1">
      <result type="constant" value="1" />
    </when>
    
    <!-- Condition 2: If temperature >= 38 -->
    <!-- Note: Use &gt;= for >= in XML -->
    <when field="temperature" operator="&gt;=" value="38">
      <result type="constant" value="1" />
    </when>
    
    <!-- Default: 0 -->
    <else>
      <result type="constant" value="0" />
    </else>
  </calculation>
</question>
