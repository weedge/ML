#!/bin/bash
#from:http://liuzhiqiangruc.iteye.com/blog/1601922
input=$1
if [ -z $input ]; then
    echo "please input the traning file"
    exit 1
fi

## pre calculate the log2 value for the later calculate operation
declare -a log2
logi=0
records=`cat $input | wc -l`
for i in `awk -v n=$records 'BEGIN{for(i=1;i<n;i++) print log(i)/log(2);}'`
do
    ((logi+=1))
    log2[$logi]=$i
done


## function for calculating the entropy for the given distribution of the class
function getEntropy {
local input=`echo $1`
if [[ $input == *" "* ]]; then
    local current_entropy=0
    local sum=0
    local i
    for i in ${input}
    do
        ((sum+=$i))
        current_entropy=$(awk -v n=$i -v l=${log2[$i]} -v o=$current_entropy 'BEGIN{print n*l+o}')
    done
    current_entropy=$(awk -v n=$current_entropy -v b=$sum -v l=${log2[$sum]} 'BEGIN{print n/b*-1+l;}')
    eval $2=$current_entropy;
else
    eval $2=0;
fi
}


### the header title of the input data
declare -A header_info;
header=$(head -1 $input);
headers=(${header//,/ })
length=${#headers[@]};
for((i=0;i<length;i++)); do
    attr=${headers[$i]};
    header_info[$attr]=$i;
done


### the data content of the input data
data=${input}_dat;
sed -n '2,$p' $input > $data



## use an array to store the information of a descision tree
## the node structure is {child,slibling,parent,attr,attr_value,leaf,class}
## the root is a virtual node with none used attribute
## only the leaf node has class flag and the "leaf,class" is meaningfull
## the descision_tree
declare -a descision_tree;

## the root node with no child\slibing and anythings else
descision_tree[0]="0:0:0:N:N:0:0";


## use recursive algrithm to build the tree 
## so we need a trace_stack to record the call level infomation
declare -a trace_stack;

## push the root node into the stack
trace_stack[0]=0;
stack_deep=1;

## begin to build the tree until the trace_stack is empty
while [ $stack_deep -ne 0 ]; do
    ((stack_deep-=1));
    current_node_index=${trace_stack[$stack_deep]};
    current_node=${descision_tree[$current_node_index]};
    current_node_struct=(${current_node//:/ });

    ## select the current data set 
    ## get used attr and their values
    attrs=${current_node_struct[3]};
    attrv=${current_node_struct[4]};

    declare -a grepstra=();

    if [ $attrs != "N" ];then
        attr=(${attrs//,/ });
        attrvs=(${attrv//,/ });
        attrc=${#attr[@]};
        for((i=0;i<attrc;i++)); do
            a=${attr[$i]};
            index=${header_info[$a]};
            grepstra[$index]=${attrvs[$i]};
        done
    fi

    for((i=0;i<length;i++)); do
        if [ -z ${grepstra[$i]} ]; then
            grepstra[$i]=".*";
        fi
    done
    grepstrt=${grepstra[*]};
    grepstr=${grepstrt// /,};
    grep $grepstr $data > current_node_data

    ## calculate the entropy before split the records
    entropy=0;
    input=`cat current_node_data | cut -d "," -f 5 | sort | uniq -c | sed 's/^ \+//g' | cut -d " " -f 1`
    echo $input;
    getEntropy "$input" entropy;

    ## calculate the entropy for each of the rest attrs
    ## and select the min one
    min_attr_entropy=1; 
    min_attr_name="";
    min_attr_index=0;
    for((i=0;i<length-1;i++)); do
        ## just use the rest attrs
        if [[ "$attrs" != *"${headers[$i]}"* ]]; then
            ## calculate the entropy for the current attr
            ### get the different values for the headers[$i]
            j=$((i+1));
            cut -d "," -f $j,$length current_node_data > tmp_attr_ds
            dist_values=`cut -d , -f 1 tmp_attr_ds | sort | uniq -c | sed 's/^ \+//g' | sed 's/ /,/g'`;
            totle=0;
            totle_entropy_attr=0;
            for k in $dist_values; do
                info=(${k//,/ });
                ((totle+=${info[0]}));
                cur_class_input=`grep "^${info[1]}," tmp_attr_ds | cut -d "," -f 2 | sort | uniq -c | sed 's/^ \+//g' | cut -d " " -f 1`
                cur_attr_value_entropy=0;
                getEntropy "$cur_class_input" cur_attr_value_entropy;
                totle_entropy_attr=$(awk -v c=${info[0]} -v e=$cur_attr_value_entropy -v o=$totle_entropy_attr 'BEGIN{print c*e+o;}');
            done
            attr_entropy=$(awk -v e=$totle_entropy_attr -v c=$totle 'BEGIN{print e/c;}');
            echo "attr:"$attr_entropy;
            echo "min_attr:"$min_attr_entropy;
            cmp=`echo "$attr_entropy < $min_attr_entropy" | bc`;
            echo $cmp;
            if [ $cmp = 1 ]; then
                min_attr_entropy=$attr_entropy;
                min_attr_name="${headers[$i]}";
                min_attr_index=$j;
            fi
        fi
    done

    ## calculate the gain between the original entropy of the current node 
    ## and the entropy after split by the attribute which has the min_entropy
    gain=$(awk -v b=$entropy -v a=$min_attr_entropy 'BEGIN{print b-a;}');

    ## when the gain is large than 0.1 and  then put it as a branch
    ##      and add the child nodes to the current node and push the index to the trace_stack
    ## otherwise make it as a leaf node and get the class flag
    ##      and do not push trace_stack
    if [ $(echo "$gain > 0.1" | bc)  = 1 ]; then
        ### get the attribute values
        attr_values_str=`cut -d , -f $min_attr_index current_node_data | sort | uniq`;
        attr_values=($attr_values_str);

        ### generate the node and add to the tree and add their index to the trace_stack
        tree_store_length=${#descision_tree[@]};
        current_node_struct[0]=$tree_store_length;
        parent_node_index=$current_node_index;

        attr_value_c=${#attr_values[@]};
        for((i=0;i<attr_value_c;i++)); do
            tree_store_length=${#descision_tree[@]};
            slibling=0;
            if [ $i -lt $((attr_value_c-1)) ]; then
                slibling=$((tree_store_length+1));
            fi

            new_attr="";
            new_attrvalue="";
            if [ $attrs != "N" ]; then
                new_attr="$attrs,$min_attr_name";
                new_attrvalue="$attrv,${attr_values[$i]}";
            else
                new_attr="$min_attr_name";
                new_attrvalue="${attr_values[$i]}";
            fi
            new_node="0:$slibling:$parent_node_index:$new_attr:$new_attr_value:0:0";
            descision_tree[$tree_store_length]="$new_node";
            trace_stack[$stack_deep]=$tree_store_length;
            ((stack_deep+=1));
        done
        current_node_update=${current_node_struct[*]};
        descision_tree[$current_node_index]=${current_node_update// /:};
    else   ## current node is a leaf node 
        current_node_struct[5]=1;
        current_node_struct[6]=`cut -d , -f $length current_node_data | sort | uniq -c | sort -n -r | head -1 | sed 's/^ \+[^ ]* //g'`;
        current_node_update=${current_node_struct[*]};
        descision_tree[$current_node_index]=${current_node_update// /:};
    fi 

    ## output the descision tree after every step for split or leaf node generater
    echo ${descision_tree[@]};
done

