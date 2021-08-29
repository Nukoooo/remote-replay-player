# Requirement
1. Bhoptimer version 3.0.7a or above (preferably after [this commit](https://github.com/shavitush/bhoptimer/commit/36a468615d0cbed8788bed6564a314977e3b775a))
2. [REST in Pawn version 1.3.0 or above](https://github.com/ErikMinekus/sm-ripext/releases/latest)
3. A callback server that can handle requests.
    - You can use backend.py or make your own one

# Installation
1. Compile the plugin with **latest shavit.inc** then drag and drop in ``addons/sourcemod/plugins``
2. Get your callback server working
    - If you want to use the example I proved please follow this:
        - Install python3 and pip3 on your server
        - Type ``pip3 install flask`` in the terminal
        - Type ``python3 backend.py`` to run the server
        - Upload replays
            - Create a folder called ``replays`` at where backend.py is
            - Create folders based on style ids
            - Put your replay files in it. The naming should follow [bhoptimer's naming style](https://github.com/shavitush/bhoptimer/blob/a521b658c251c76b7bf6d14942c084b987218850/addons/sourcemod/scripting/shavit-replay.sp#L2110)


3. Change ``addons/sourcemod/configs/remote-replay-player.cfg`` according to your database tables
    - If ``use_mysql`` is **1 or above** then you need to add this to your ``addons/sourcemod/configs/database.cfg``
        ```
        "rrp"
        {
            "driver"			"mysql"
            "host"			"your_server_host"
            "database"			"your_database_name"
            "user"			"your_user_name"
            "pass"			"your_password"
        }
        ```
    - If you have mysql table prefix set then you should add it too. *Example: iamprefix_users*